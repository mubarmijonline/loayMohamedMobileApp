# Videos are slow to start — the backend half

Written 2026-09-11. Students report that lesson videos take too long to start,
and that seeking is slow. The app side is being fixed alongside this: a proper
seek bar, ±10 s skip, and no longer firing API refreshes that compete with the
video while it loads. This document is the server side.

---

## Prompt for your backend developer

> Our Flutter app plays lesson videos from
> `GET /api/v1/student/content/<id>/drive-stream`, which proxies each file from
> Google Drive. Students wait too long for playback to start, and every seek is
> slow. The phone's player (AVPlayer on iOS, ExoPlayer on Android) fetches the
> file with HTTP **Range** requests: a tiny probe first (`bytes=0-1`), then the
> parts it needs, then a new range on every seek. Each of those requests goes
> through our server to Google Drive and back.
>
> Please:
>
> 1. **Measure first**, with the commands in the document below:
>    time-to-first-byte for `Range: bytes=0-1` and for a range near the end of
>    the file. Target: under 300 ms each.
> 2. Make the handler **stream the requested range** from Drive instead of
>    downloading the whole file first: forward the client's `Range` header to
>    Drive, and answer `206 Partial Content` with `Content-Range`,
>    `Content-Length` and `Accept-Ranges: bytes`.
> 3. **Cache** the Google access token (it is valid for about an hour) and each
>    file's size and MIME type, and reuse one HTTP connection to Google. None of
>    that should happen on every request.
> 4. **Turn off nginx buffering** for this route (`proxy_buffering off;`, or
>    send `X-Accel-Buffering: no`) so bytes reach the phone as they arrive.
> 5. Check every MP4 has its `moov` atom at the front ("faststart"). If not,
>    remux it with `ffmpeg -i in.mp4 -c copy -movflags +faststart out.mp4`. That
>    changes nothing about quality and takes seconds per file.
> 6. Longer term, move lessons to **Bunny Stream** or **Cloudflare Stream**. The
>    app already plays both (`provider: "bunny"` or `"cloudflare"` from
>    `/embed`) with no app update.
>
> Full detail, a reference handler and the nginx settings are in
> `docs/mobile/BACKEND_VIDEO_STREAMING.md` in the mobile repository.

---

## Measure first

```bash
T="<access token of a TEST student>"
ID="<id of a content item with a Drive video>"
URL="https://loaymotawie.com/api/v1/student/content/$ID/drive-stream"

# 1. The probe every player sends first. Expect 206, well under a second.
curl -s -o /dev/null -H "Authorization: Bearer $T" -H "Range: bytes=0-1" \
  -w 'status %{http_code}  first byte %{time_starttransfer}s\n' "$URL"

# 2. The headers the player relies on. Expect 206, Accept-Ranges: bytes,
#    Content-Range: bytes 0-1/<total size>, Content-Length: 2.
curl -s -D - -o /dev/null -H "Authorization: Bearer $T" -H "Range: bytes=0-1" "$URL"

# 3. A range near the end, which is what a seek costs (and what a file without
#    faststart costs before it can play at all). Use the total size from step 2.
curl -s -o /dev/null -H "Authorization: Bearer $T" \
  -H "Range: bytes=<total minus 1000000>-" \
  -w 'status %{http_code}  first byte %{time_starttransfer}s\n' "$URL"

# 4. Throughput. Should be several MB/s on a good connection.
curl -s -o /dev/null -H "Authorization: Bearer $T" -H "Range: bytes=0-20000000" \
  -w 'speed %{speed_download} bytes/s\n' "$URL"
```

| What you see | What it means | Fix |
|---|---|---|
| Step 1 takes seconds, and longer for longer videos | The handler downloads the whole file before answering | 2 |
| Step 1 answers `200`, or has no `Content-Range` | Ranges are not supported, so the player downloads from the start to reach any point — seeking costs as much as watching | 2 |
| Every request, however small, costs 0.5–1 s | A new Google token or a new TLS connection on each request | 3 |
| Bytes arrive in one burst at the end | nginx is buffering the response | 4 |
| Steps 1–3 are fast, but playback still waits | The file is not faststart | 5 |

## Reference handler (Flask)

The helper names are placeholders for what your code already has. What matters
is the shape: forward the range, stream the body, pass the range headers back.

```python
import requests
from flask import Response, request, stream_with_context

_google = requests.Session()  # one keep-alive connection to Google, reused

@bp.get("/student/content/<content_id>/drive-stream")
@require_student                                         # existing auth
def drive_stream(content_id):
    item = authorised_content_or_404(content_id)         # existing class check
    token = cached_drive_token()                         # refresh ~every 55 min
    meta = cached_drive_meta(item.drive_file_id, token)  # size + mimeType

    headers = {"Authorization": f"Bearer {token}"}
    if "Range" in request.headers:
        headers["Range"] = request.headers["Range"]

    upstream = _google.get(
        f"https://www.googleapis.com/drive/v3/files/{item.drive_file_id}",
        params={"alt": "media"},
        headers=headers,
        stream=True,              # never read the whole file into memory
        timeout=(5, 60),
    )
    resp = Response(
        stream_with_context(upstream.iter_content(chunk_size=64 * 1024)),
        status=upstream.status_code,  # 206 for a range, 200 for the whole file
    )
    resp.headers["Content-Type"] = meta.get("mimeType", "video/mp4")
    resp.headers["Accept-Ranges"] = "bytes"
    for name in ("Content-Length", "Content-Range"):
        if name in upstream.headers:
            resp.headers[name] = upstream.headers[name]
    resp.headers["X-Accel-Buffering"] = "no"   # tell nginx to stream it
    return resp
```

A streaming response holds a worker for as long as the student watches. With
gunicorn's default sync workers, a handful of students watching at once will
queue everyone else: use gevent workers, or considerably more workers.

## nginx

```nginx
location ~ ^/api/v1/student/content/[^/]+/drive-stream$ {
    proxy_pass http://<your app upstream>;
    proxy_buffering off;          # pass bytes on as they arrive
    proxy_request_buffering off;
    proxy_read_timeout 300s;      # long lessons
}
```

## Faststart check

```bash
ffprobe -v trace lesson.mp4 2>&1 | grep -m2 -oE "type:'(moov|mdat)'"
# moov before mdat: fine.  mdat first: remux with -movflags +faststart.
```

---

## The fix that actually makes it fast

Proxying Google Drive will always be the slow path. Drive is file storage, not a
video service: it has no copies near your students, it sends one quality
regardless of their connection, and every seek is a round trip from the phone
to your server, to Google, and back.

Streaming services exist to solve exactly this. They convert each video into
several qualities, serve it from servers close to the student, and switch
quality with the connection. Playback typically starts in about a second, even
on mobile data.

The app already supports two of them. When `/embed` returns `provider: "bunny"`
with a signed URL, or `provider: "cloudflare"`, the app plays it in its protected
player — watermark, no share button, navigation locked — **without an app
update**. Moving a lesson is:

1. Upload the video to a Bunny Stream library (or Cloudflare Stream).
2. Store its video id on the content item.
3. Have `/embed` return `provider: "bunny"` and the signed URL for items that
   have one, and fall back to Drive for items that do not.

Lessons can move one at a time, starting with the most-watched.
