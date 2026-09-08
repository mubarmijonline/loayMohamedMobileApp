# Videos do not play on mobile — `drive-stream` was never deployed

Captured **2026-09-08** against `https://loaymotawie.com`. Everything below is
a verbatim `curl` transcript, not a reconstruction.

**Summary:** the Drive proxy endpoint the mobile app is required to play
(`API_BRIEF §6`: *"Play `stream_url`. Ignore `embed_url` unless `stream_url` is
missing."*) returns **404**. No client change can fix this. Two client-side
bugs were found and fixed in the same pass, but the endpoint is the blocker.

---

## 1. The evidence

Unauthenticated `GET`, same bogus content id (`000000000000000000000000`) for
every row, so the only variable is the route itself:

| Route | Status | Body |
|---|---|---|
| `/api/v1/student/content/<id>/embed` | `401` | `{"error":{"code":"missing_token",…},"success":false}` |
| `/api/v1/student/content/<id>/thumbnail` | `401` | `{"error":{"code":"missing_token",…},"success":false}` |
| `/api/v1/student/content` | `401` | `{"error":{"code":"missing_token",…},"success":false}` |
| `/api/v1/student/classes` | `401` | `{"error":{"code":"missing_token",…},"success":false}` |
| **`/api/v1/student/content/<id>/drive-stream`** | **`404`** | **`{"error":"Not found"}`** |

Two things to read off this table.

**`drive-stream` does not exist.** Auth runs before the id lookup on every
other route here — a nonexistent content id still returns `401`, never `404`.
So a `404` on this path is the router failing to match, not the id failing to
resolve. The body confirms it: `{"error": "Not found"}` is the bare Flask 404,
not the `{success, error:{code,message}}` envelope every real mobile route
returns. Same signature `/student/classes` had when it was missing.

**`/student/classes` now exists.** It was `404` on 2026-09-07 and is `401`
today, so the content-grouping work from `BACKEND_CONTENT_GROUPING.md` has
partly shipped. `drive-stream` is what did not come with it.

Reproduce:

```bash
for p in embed drive-stream thumbnail; do
  printf '%-14s ' "$p"
  curl -s -o /dev/null -w '%{http_code}\n' \
    "https://loaymotawie.com/api/v1/student/content/000000000000000000000000/$p"
done
```

Expected once fixed: `401 401 401`. Today: `401 404 401`.

---

## 2. Why this is a black screen and not an error message

The app asks `/embed` for the video, and then:

- If `stream_url` is present, it plays it natively with the bearer token
  attached. Against a `404` that surfaces as *"This video could not be
  played."*
- If `stream_url` is **absent**, it falls back to `embed_url` — the *public*
  `https://drive.google.com/file/d/<id>/preview`. For a **private** Drive file
  Google renders its own sign-in wall inside the iframe without navigating
  anywhere, so the app's navigation guard never fires and the student sees a
  **black rectangle** with a working watermark on top. This matches the
  reported symptom exactly, and matches the `401` already confirmed on that
  preview URL on 2026-09-06.

`embed_url` is also a content leak independent of this bug: it is unsigned,
permanent, identical for every student, and playable by anyone holding the
link with no account at all. That is the reason `stream_url` exists.

---

## 3. What to deploy

`GET /api/v1/student/content/<content_id>/drive-stream`

1. Authenticate the bearer token; `401` on a missing/expired one, using the
   standard envelope.
2. Authorise: the student must be in a class that owns `content_id` — the same
   `_get_student_class_ids` check `/student/content` already uses. `403`
   otherwise.
3. Fetch the file with the Drive **service account** and stream the bytes
   back. The Drive file id must never appear in the response, its headers or
   the URL.
4. Required response headers, or seeking and resume break:
   - `Content-Type: video/mp4`
   - `Accept-Ranges: bytes`
   - honour the request's `Range` header and reply `206 Partial Content` with
     a correct `Content-Range`. The player issues a `Range` request for
     **every** seek and for resume-from-position.
   - `Content-Length` on both the `200` and the `206`.

Then make `/embed` return it:

```json
{
  "provider": "drive",
  "stream_url": "/api/v1/student/content/<content_id>/drive-stream",
  "embed_url": "",
  "watermark": "Sara Ali · +201200000000 · 65f0abc",
  "duration": 1326
}
```

A relative path is fine — the app resolves it against the API origin. An
absolute URL on the same origin is fine too.

### Please also send `provider`

`provider` is currently absent or unrecognised on some rows. The app no longer
depends on it for player selection (see §4), but it is still the field that
says whether a URL is signed and needs re-minting before it expires.

---

## 4. What was fixed on the client in this pass

Both were real, both were silent, and both are now covered by tests that fail
against the old code:

1. **A relative `stream_url` was never made absolute.** `Uri.tryParse`
   accepts a bare path and returns a valid *relative* `Uri`, so the null check
   passed and `/api/v1/…/drive-stream` went straight to AVPlayer/ExoPlayer,
   which cannot open it and reports nothing. Now resolved against the API
   origin at the repository boundary.
2. **The WebView branch loaded `embed_url` rather than the stream URL,** and
   the branch was chosen by the `provider` string — so a missing `provider`
   routed a perfectly good proxy URL into a WebView pointed at the public
   Google preview. Player selection is now decided by whether the URL is on
   our own origin, which is also what decides whether the bearer token may be
   attached.

With `drive-stream` deployed, videos play with **no further client change**.
Until then the student gets a clear error instead of a black frame.
