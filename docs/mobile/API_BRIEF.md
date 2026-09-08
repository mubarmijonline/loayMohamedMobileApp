# Loay Motawie — Mobile API Brief (Flutter)

Verified against source on 2026-09-04. Every route below was read from
`backend/app/blueprints/`, not from memory. Where behaviour is surprising or
looks wrong, it is flagged inline.

Blueprints that answer under `/api/v1`
(`backend/app/__init__.py:285-287`):

| Blueprint | File | Covers |
|---|---|---|
| `mobile_api` | `backend/app/blueprints/mobile_api/__init__.py` | student app, auth, devices |
| `parent_api` | `backend/app/blueprints/parent/__init__.py` | parent register/login, parent reads |
| `parent_otp_api` | `backend/app/blueprints/parent_otp/__init__.py` | parent OTP login |

---

## 1. Transport

- Base URL: `https://loaymotawie.com/api/v1` (`nginx/loay_mohamed.conf:16`).
- All request bodies are JSON unless the route says `multipart/form-data`.
- Auth header: `Authorization: Bearer <access_token>`.
- CSRF is exempt for the whole mobile blueprint
  (`mobile_api/__init__.py:23`). No CSRF token needed.
- No CORS config exists in the backend. Irrelevant for a native client;
  it will bite a Flutter **web** build.

### Response envelope

Every mobile route uses the same two shapes
(`mobile_api/__init__.py:59-68`):

```json
{ "success": true, "data": <payload> }
```

```json
{ "success": false, "error": { "message": "human text", "code": "machine_code" } }
```

`error.code` is only present when the route passed one. `error.message` is
always present and is written for the end user — safe to show directly.

---

## 2. Tokens — read this before writing the auth layer

The tokens are **not JWTs**. They are `itsdangerous.URLSafeTimedSerializer`
values signed with `SECRET_KEY`, salt `mobile-api-token`
(`mobile_api/__init__.py:70-102`).

Consequences for the client:

1. Do not use a JWT decoder. Do not try to read `exp` out of the token.
2. Expiry is **not baked into the token**. It is enforced at verification time
   from server config `MOBILE_ACCESS_TOKEN_TTL_SECONDS` (default 3600) and
   `MOBILE_REFRESH_TOKEN_TTL_SECONDS` (default 2592000 / 30 days)
   (`backend/app/config.py:114-115`). The server can shorten or lengthen the
   life of already-issued tokens by changing that config.
3. Track expiry client-side from the `expires_in` / `refresh_expires_in`
   fields returned on login. Refresh proactively at ~80% of `expires_in`.
4. Payload carries `uid`, `role`, `type`, `tv` (token version).

### Session revocation

`mobile_auth_required` rejects a request when
(`mobile_api/__init__.py:111-158`):

| Condition | HTTP | `code` |
|---|---|---|
| No/short `Authorization` header | 401 | `missing_token` |
| TTL exceeded | 401 | `token_expired` |
| Bad signature or wrong token type | 401 | `invalid_token` |
| `uid` not an ObjectId | 401 | `invalid_payload` |
| User row gone | 401 | `user_not_found` |
| `is_blocked == true` or `is_active == false` | 403 | `account_blocked` |
| Token `tv` != user `token_version` | 401 | `session_revoked` |
| Route is student-only and role != student | 403 | `forbidden` |

**`POST /auth/logout` increments `token_version`**
(`mobile_api/__init__.py:567-579`). That kills **every** access and refresh
token for that user on **every** device, not just the one logging out. Design
the UX accordingly, or expect users to be signed out of their other phone.
There is no per-device logout.

On `session_revoked` or `token_expired`, the app must clear stored tokens and
route to login. Do not retry.

---

## 3. Auth

### `POST /auth/register`
`mobile_api/__init__.py:287`. Public. Students only.

Body (snake_case or camelCase accepted for the paired fields):

| Field | Required | Rules |
|---|---|---|
| `name` or `full_name` | yes | >= 2 chars |
| `email` | yes | must contain `@`, stored lowercased |
| `phone` | yes | normalised to E.164 with `country_code` |
| `country_code` / `countryCode` | no | default `+20` |
| `parent_phone` / `parentPhone` | yes | valid, and **must differ from `phone`** |
| `parent_country_code` / `parentCountryCode` | no | defaults to `country_code` |
| `school` | yes | non-empty |
| `grade` | yes | int, one of `9, 10, 11, 12` |
| `password` | yes | >= 6 chars |
| `role` | no | anything but `student` → 403 `forbidden_role` |

`201` → `{ access_token, refresh_token, token_type: "Bearer", expires_in,
refresh_expires_in, user }`

Errors: `400 validation_error` (all failures joined with `; ` into one
message — show it verbatim), `409 email_exists`, `409 phone_exists`,
`403 forbidden_role`.

### `POST /auth/login`
`mobile_api/__init__.py:390`. Public.

Body: `{ identifier, password }`. `identifier` also accepted as `email` or
`phone`. If it contains `@` it is looked up as an email; otherwise it goes
through `phone_lookup_variants`, so `01200588803`, `+201200588803`,
`00201200588803`, `1200588803` and spaced/dashed forms all resolve. On a
successful login with a legacy format, the stored phone is self-healed to
E.164.

`200` → same payload as register.
Errors: `400 missing_credentials`, `401 invalid_credentials`,
`403 account_blocked`.

### `POST /auth/social`
`mobile_api/__init__.py:452`. Public. Apple and Google sign-in.

Body: `{ provider: "apple"|"google", id_token, nonce?, email?, name?,
authorization_code?, device_id? }`

- `nonce` is the **raw** nonce, Apple only.
- `email` / `name` are fallbacks used only at first sign-up, when the
  provider withholds them.
- Match order: `providers.<provider>.sub`, then email, then create.

`200` → same payload as login.
Errors: `400 invalid_provider`, `400 missing_token`, `401 invalid_token`,
plus whatever `SocialAuthError` / `SocialLoginError` raise.

Note: `PATCH /student/profile` rejects `@privaterelay.appleid.com` addresses
with `422 relay_email_not_allowed` (`mobile_api/__init__.py:1450`). If Apple
sign-in produced a relay address, prompt for a real one before the user hits
that wall.

### `POST /auth/refresh`
`mobile_api/__init__.py:531`. Public.

Body: `{ refresh_token }` — or send the refresh token as the Bearer header.

`200` → `{ access_token, refresh_token, token_type, expires_in,
refresh_expires_in }`. **Both tokens rotate.** Store the new refresh token or
the next refresh fails.

Errors: `400 missing_refresh_token`, `401 refresh_expired`,
`401 invalid_refresh_token`, `401 invalid_payload`, `401 user_not_found`,
`403 inactive_account`.

Gap worth knowing: refresh does **not** check `token_version`, so a refresh
token still mints a fresh access token straight after logout. The access token
it mints is then rejected by `mobile_auth_required` on the `tv` check, so
nothing leaks — but the client sees a successful refresh followed by a 401.
Treat `session_revoked` as terminal regardless of refresh success.

### `POST /auth/logout`
`mobile_api/__init__.py:567`. Auth (student or parent).
`200` → `{ logged_out: true }`. See revocation note above.

### `GET /auth/me`
`mobile_api/__init__.py:643`. Auth (student or parent).
`200` → the user object. For a parent, also `linked_students: [...]`.

### User object
`_user_public`, `mobile_api/__init__.py:161-197`:

```
_id, id, full_name, name, email, phone, parent_phone, school, grade, role,
is_active, must_change_password, email_verified, phone_verified,
parent_phone_verified, profile_image_url, avatar_url, apple_user_id,
apple_email_relay, auth_methods[], has_password, created_at, last_login_at
```

`_id`/`id` and `full_name`/`name` and `profile_image_url`/`avatar_url` are
duplicate aliases. Pick one per pair in the Dart model.

---

## 4. Push devices (OneSignal)

### `POST /devices/register`
`mobile_api/__init__.py:581`. Auth (student or parent).

Body: `{ player_id, platform?: "ios"|"android"|"web", app_version?,
device_model?, os_version?, role?: "student"|"parent" }`

`player_id` max 128 chars. A `role` that disagrees with the token's role is
overridden by the token — a student cannot register as a parent.

`200` → `{ registered: true, player_id, device_id, role }`
Errors: `422 invalid_player_id`, `422 invalid_platform`, `422 invalid_role`.

### `DELETE /devices/<player_id>`
`mobile_api/__init__.py:626`. Auth.
`200` → `{ unregistered: true }`. `403 forbidden_device` if the device row
belongs to another account.

**Call this before `/auth/logout`**, otherwise push keeps landing on a device
that is signed out (the code comment says so at `mobile_api/__init__.py:569`).

Server env: `ONESIGNAL_APP_ID`, `ONESIGNAL_REST_API_KEY`
(`backend/app/services/push.py:45-46`).

---

## 5. Student — dashboard and catalogue

### `GET /student/dashboard`
`mobile_api/__init__.py:665`.

```json
{ "success": true, "data": {
  "classes": [ { "_id", "name", "teacher_name" } ],
  "homework_assignments": [ <assignment> ],
  "quiz_assignments":     [ <assignment> ],
  "content_items": [ { "_id","title","type","class_id","class_name","watched","created_at" } ],
  "announcements": [ <announcement> ],
  "kpis": { "not_submitted": 0, "total_content": 0 }
} }
```

Announcements here are global plus any scoped to the student's classes.
`not_submitted` counts homework + quizzes in state `pending` or `overdue`.

### `GET /student/subjects`
`mobile_api/__init__.py:729`. Reads the `teacher_classes` collection.

Query params: `filter=enrolled|available`, `grade=<int>`,
`exam_board=<string>`.

```json
{ "subjects": [ { ...class doc..., "is_enrolled": bool, "is_pending": bool,
                  "enrollment_status": "active"|"pending"|"none",
                  "grade": int|null, "exam_board": str|null } ],
  "filters": { "filter": str|null, "grade": int|null, "exam_board": str|null },
  "counts":  { "total": n, "enrolled": n, "pending": n, "available": n } }
```

`filter=available` excludes both enrolled and pending items.

### `GET /student/subjects/<subject_id>`
`mobile_api/__init__.py:803`.

**Broken pairing — do not build a screen on this.** The list route reads
`teacher_classes`; this detail route reads the `subjects` collection
(`mobile_api/__init__.py:811`). An `_id` taken from the list will 404 here.
Render detail from the object already in the list response, or ask for the
backend fix. Returns `404 not_found` / `400 invalid_subject`.

### `POST /student/enrollment-requests`
`mobile_api/__init__.py:815`. Body `{ subject_id }`.
`201` → `{ created: true }`.
Errors: `400 missing_subject`, `409 already_pending`, `409 already_enrolled`.

### `GET /student/enrollments`
`mobile_api/__init__.py:848`.
`200` → array of `{ _id, subject_id, subject_title, status, enrolled_at }`.

**`subject_title` is always empty.** It reads `.title` off a `teacher_classes`
document, and those carry `name`, not `title`
(`mobile_api/__init__.py:892`). Show the class name from
`/student/subjects` instead until the backend is fixed.

### `GET /student/subjects/<subject_id>/lessons`
`mobile_api/__init__.py:872`. Requires an active enrollment.
`200` → array of lesson docs sorted by `order_index`.
Errors: `400 invalid_subject`, `410 subject_closed`, `403 not_enrolled`.

### `GET /student/progress/<subject_id>`
`mobile_api/__init__.py:1174`.
`200` → `{ total_watched_seconds, completion_percent }`, zeros when no row.

---

## 6. Student — content and video

### Access rule, enforced on every content route

1. `content_items` doc must exist → else `404 not_found`.
2. `is_visible` must not be `false` → else `404 not_available`.
3. `item.class_id` must be in the student's active `class_students` rows →
   else `403 not_enrolled` (`mobile_api/__init__.py:199-201`).

### `GET /student/classes`

Per-class progress, matching the portal's `/api/student/classes`. This is what
fills the section header in the Videos screen ("Mobile Trial - AS Edexcel",
"6/10 watched").

`200` -> array of:

```json
{ "_id", "name", "level", "subject", "teacher_name", "cover_url", "exam_board",
  "is_active",
  "homework_total", "homework_done", "quiz_total", "quiz_done",
  "video_total", "video_watched",
  "pending_tasks", "completed_tasks", "total_tasks", "completion_percent" }
```

### `GET /student/content`

All visible content across the student's **active** classes.

**Sorted by `(class_id, group_title, order_index, created_at)`** - the same
order the web portal returns. Render it in the order given; do not re-sort, or
the two clients will disagree about section order.

`200` -> array of:

```json
{ "_id", "title", "type", "description",
  "group_title", "class_id", "class_name",
  "duration_seconds", "order_index",
  "thumbnail_url", "provider", "watched", "created_at" }
```

- `group_title` is the folder name the teacher set. Items with none come back
  as the literal `"(Ungrouped)"`, never null, so the client does not need a
  special case for it.
- `order_index` is the `#1` / `#2` badge. It is per group, not global.
- `thumbnail_url` is `/api/v1/student/content/<id>/thumbnail` when the item has
  a thumbnail source, otherwise `null`.
- `provider` is `bunny`, `cloudflare`, `drive` or `null`.
- `watched` reads `watch_progress.watched`.

**The API returns a flat list, not a tree.** The portal groups it client-side
and so should the app: walk the list in order, start a new section whenever
`class_id` or `group_title` changes. Counting distinct `group_title` per class
gives the "4 groups - 10 videos" line.

### `GET /student/content/<content_id>/thumbnail`

Auth. Returns the poster image, or a generated placeholder when the item has
none. Bunny thumbnails are proxied; Cloudflare and stored `thumbnail_url`
values are 302 redirects.

Send the auth header. This is not a public URL, so an image widget that cannot
attach headers will get a 401.

### `GET /student/content/<content_id>`

`200` ->

```json
{ "_id","title","type","description",
  "group_title","order_index","duration_seconds",
  "embed_url", "stream_url",
  "provider", "stream_uid", "bunny_video_id", "watermark" }
```

### `GET /student/content/<content_id>/embed`

Same guards, video-only payload: `embed_url`, `stream_url`, `provider`,
`title`, `duration_seconds`, `stream_uid`, `bunny_video_id`, `watermark`.
`404 no_video` when the item has no playable source.

### Provider precedence, and which URL to play

Resolved in this order:

| Order | Field | `provider` | `stream_url` | `embed_url` |
|---|---|---|---|---|
| 1 | `bunny_video_id` | `bunny` | signed iframe, share/pip off | same |
| 2 | `stream_uid` | `cloudflare` | `https://iframe.videodelivery.net/<uid>` | same |
| 3 | `drive_file_id` | `drive` | `/api/v1/student/content/<id>/drive-stream` | Google preview URL |

**Play `stream_url`. Ignore `embed_url` unless `stream_url` is missing.**

For Drive the two now differ, and that difference is the whole point:

- `stream_url` is a proxy on our own origin. The backend fetches the bytes with
  the Drive service account and forwards them. The Drive file id never reaches
  the device, there is no Google player, and therefore no share button, no
  pop-out and no download item to hide. It serves raw `video/mp4` with
  `Accept-Ranges: bytes` and forwards the client's `Range` header, so seeking
  works in a native player.
- `embed_url` is still the unsigned public
  `https://drive.google.com/file/d/<id>/preview`. It is kept only so builds
  already in the field keep working. **Treat it as deprecated.** Anyone with
  that string can watch the video without an account.

`watermark` is now returned for **every** provider, not just Bunny. Format:
`Full Name - Phone - user id`. Previously Drive, the one unsigned provider, was
the only one the app had nothing to draw.

Bunny `embed_url` carries `share=false&sharing=false&pip=false` plus
`autoplay`, `muted`, `playsinline`, `preload` and `responsive`, matching the
portal. Without those the Bunny player draws its own share button.

### `GET /student/content/<content_id>/drive-stream`

Auth. The Drive video's bytes. Honours `Range`, returns `200` or `206`,
`Accept-Ranges: bytes`, `Cache-Control: private, no-store`.

`503` when the Drive service account is not configured, `502` when the file has
not been shared with the service account, `404 no Drive video` when the item is
not a Drive item.

Shares one implementation with the portal:
`backend/app/services/drive_stream.py`.

### `GET /student/content/<content_id>/resume`
`mobile_api/__init__.py:1153`.
`200` → `{ resume_from, total_watched, completion_percent }`, zeros when the
student has never opened it. Seek to `resume_from` on open.

Note: this route does **not** re-check enrollment — it only reads the caller's
own progress row, so there is nothing to leak.

---

## 7. Student — assignments and quizzes

Homework and quizzes are one `assignments` collection separated by
`type: "homework" | "quiz"`.

### `GET /student/assignments`
`mobile_api/__init__.py:1194`. Query `?type=homework|quiz`.
`GET /student/quizzes` (`:1212`) is the same call with `type=quiz`.

Each item (`_get_assignments_for_student`, `:204-248`):

```json
{ "_id","title","type","description","class_id","class_name",
  "due_at","created_at",
  "submission_status": "graded"|"submitted"|"overdue"|"pending",
  "submission_states": ["submitted","late",...],
  "submission": <student-safe submission>|null,
  "attachment": <raw attachment dict>|null }
```

`submission_states` is the full set, in a stable render order.
`submission_status` collapses it by precedence
`graded > submitted > overdue > pending`
(`backend/app/services/submission_state.py:34-43`). `late` is an adjective
that rides alongside `submitted` — render both chips.

Note the `status` query param in the old `MOBILE_API_ENDPOINTS.txt` does not
exist. Filter client-side on `submission_status`.

### `GET /student/assignments/<assignment_id>`
`mobile_api/__init__.py:1220`.

```json
{ "assignment": { ...doc..., "class_name",
                  "attachment_url", "attachment_filename",
                  "attachment_mime", "attachment_size" },
  "submission": <student-safe submission>|null }
```

The `attachment_*` keys appear only when an attachment exists.
`attachment_url` is `/api/v1/student/assignments/<id>/attachment` — a
**token-protected** path, so fetch it with the Dio/http client and the auth
header, not with `Image.network` or a bare WebView.

Errors: `400 invalid_assignment`, `404 not_found`, `403 forbidden`.

### Student-safe submission shape

`backend/app/services/marking/student_view.py:140-167`. Whitelisted on
purpose — the raw document carries marker-only fields.

Always present: `_id, assignment_id, status, submitted_at, graded_at,
file_path, file_name, files, text_content, answer_text`, plus `released`.

When `released == false`: `grade`, `feedback` are **removed**, `marking` and
`annotated_url` are `null`. Do not show a mark. Show "awaiting release".

When `released == true`: adds `grade`, `feedback`, `annotated_url`, and

```json
"marking": {
  "parts": [ { "label","topic","max","awarded","comment","ok" } ],
  "total_awarded": n, "total_max": n, "percentage": n,
  "strengths": [str], "priorities": [str], "target": str,
  "exam": { "number","session","board" }
}
```

Totals are recomputed server-side from the parts, so the breakdown and the
total can never disagree. `ok` is derived (`awarded == max`), not stored.

### `GET /student/assignments/<assignment_id>/attachment`
`mobile_api/__init__.py:1275`. Auth. Returns the binary as an attachment
download. `404 no_attachment` when there is none.

### `GET /student/assignments/<assignment_id>/graded.pdf`
`mobile_api/__init__.py:1306`. Auth. The AI-annotated paper, inline PDF.
Only served once the teacher approves: `404 no_annotated` if not rendered,
`403 not_released` while `ai_status != "approved"` and `status != "graded"`.

### `POST /student/assignments/<assignment_id>/submit`
`mobile_api/__init__.py:1335`. Two encodings.

**A. `multipart/form-data`**
- `text_content` — optional string
- `answers` — optional **JSON string** (parsed server-side; malformed → `400
  invalid_answers`)
- files under `attachments[]`, `attachments`, or `attachment` — **multiple
  files accepted**, all saved, first one mirrored into the legacy
  `file_path` / `file_name` fields

**B. `application/json`**
- `{ text_content | answer_text, answers }` — **no file can be sent this way**

At least one of text / answers / files is required, else `400
empty_submission`.

`201 { created: true }` first time, `200 { updated: true }` on resubmit.
Errors: `400 invalid_assignment`, `400 invalid_attachment`, `403 forbidden`,
`404 not_found`, `409 already_graded`.

Resubmission is allowed until `status == "graded"`.

---

## 8. Student — profile

| Route | File | Notes |
|---|---|---|
| `GET /student/profile` | `:1417` | same user object as `/auth/me` |
| `PATCH /student/profile` | `:1423` | see below |
| `PATCH /student/profile/phone` | `:1581` | `{ phone, country_code? }` |
| `POST /student/profile/avatar` | `:1519` | multipart `avatar` or `file` |
| `POST /student/profile/change-password` | `:1603` | see below |

**`PATCH /student/profile`** accepts any subset of `full_name`/`name`,
`email`, `phone` + `country_code`, `parent_phone` + `parent_country_code`,
`school`, `grade`. Sending none → `400 no_fields`.

Side effects: changing `email` sets `email_verified = false`; changing
`phone` sets `phone_verified = false`; changing `parent_phone` sets
`parent_phone_verified = false`.

Errors: `400 invalid_name|invalid_email|invalid_phone|invalid_parent_phone|
invalid_school|invalid_grade|parent_phone_conflict`,
`409 email_taken|phone_exists`, `422 relay_email_not_allowed`.

**Avatar**: `jpg|jpeg|png|webp`, MIME must be `image/jpeg|png|webp`, max
5 MB. `200` → `{ avatar_url, avatar_key, user }`. `avatar_url` is
`/uploads/avatars/<file>` — public when `USE_LOCAL_STORAGE=true`.
Errors: `400 missing_avatar|invalid_file_type|invalid_mime|file_too_large`.

**Change password**: `{ current_password, new_password, confirm_password }`,
new one >= 6 chars. `200` → `{ changed: true }`. Errors:
`400 invalid_current_password|weak_password|password_mismatch`.
It clears `must_change_password` but does **not** bump `token_version` —
other devices stay signed in after a password change.

---

## 9. Announcements and notifications

Both accept student **and** parent tokens.

### `GET /announcements`
`mobile_api/__init__.py:1632`. Query `?scope=global|subject|class&id=<oid>`.
Scoped queries always include global items too. Limit 20, newest first.
`200` → array of announcement docs.

### `GET /notifications`
`:1651`. Limit 50, newest first.
`200` → `{ notifications: [...], unread_count: n }`

### `GET /notifications/latest`
`:1667`. `200` → **the single most recent unread doc, or `null`.** Not a list.

### `POST /notifications/mark-read`
`:1678`. Body `{ notification_id }`. **Omit `notification_id` and it marks
everything read.** `200` → `{ updated: true }`.

### `POST /notifications/mark-all-read`
`:1697`. `200` → `{ updated: true }`.

Scoping (`_notif_query_for_current_user`, `:268-285`): a student sees rows
where `recipient_id` or `user_id` is them; a parent additionally sees rows
whose `student_id` is one of their linked children. Unread is `is_read:
false`.

---

## 10. Parent API

Only build these if the app ships a parent mode.

### Password auth
- `POST /auth/parent/register` — `parent/__init__.py:42`
- `POST /auth/parent/login` — `parent/__init__.py:124`
- `GET  /parent/relink` — `parent/__init__.py:200`

### OTP auth
- `POST /auth/parent/otp/request` — `parent_otp/__init__.py:177`
  Body `{ phone, country_code? }`. The phone must already appear as
  `parent_phone` on at least one student, else `404 parent_not_linked`.
  Rate-limited server-side.
- `POST /auth/parent/otp/verify` — `parent_otp/__init__.py:278`
  Body `{ phone, code (6 digits), country_code?, device_id? }`.
  `400 invalid_phone`, `400 invalid_code_format`.

### Parent reads (all require a parent token)
`parent/__init__.py`, paginated where noted:

| Route | Line |
|---|---|
| `GET /parent/students` | `:266` |
| `GET /parent/students/<id>/assignments` | `:376` |
| `GET /parent/students/<id>/quizzes` | `:393` |
| `GET /parent/students/<id>/reports` | `:410` |
| `GET /parent/students/<id>/attendance` | `:499` |
| `GET /parent/students/<id>/progress` | `:597` |
| `GET /parent/students/<id>/notifications` | `:675` |

---

## 11. Static files

`GET /uploads/<path>` — public when `USE_LOCAL_STORAGE=true`. Serves
submissions, avatars and thumbnails. **No auth.** Never put anything
sensitive behind it; use the token-protected `/attachment` and `/graded.pdf`
routes for graded work.

---

## 12. Error codes, complete

Collected from every `_err(...)` call in the three blueprints.

**Auth / session**: `missing_token`, `token_expired`, `invalid_token`,
`invalid_payload`, `user_not_found`, `account_blocked`, `session_revoked`,
`forbidden`, `forbidden_role`, `missing_credentials`, `invalid_credentials`,
`inactive_account`, `missing_refresh_token`, `refresh_expired`,
`invalid_refresh_token`, `invalid_provider`

**Registration / profile**: `validation_error`, `email_exists`,
`phone_exists`, `email_taken`, `invalid_name`, `invalid_email`,
`invalid_phone`, `invalid_parent_phone`, `parent_phone_conflict`,
`invalid_school`, `invalid_grade`, `phone_required`, `no_fields`,
`relay_email_not_allowed`, `missing_avatar`, `invalid_file_type`,
`invalid_mime`, `file_too_large`, `invalid_current_password`,
`weak_password`, `password_mismatch`

**Content / video**: `invalid_content`, `missing_content`, `not_found`,
`not_available`, `not_enrolled`, `no_video`

**Subjects / enrollment**: `invalid_subject`, `missing_subject`,
`subject_closed`, `already_pending`, `already_enrolled`

**Assignments**: `invalid_assignment`, `invalid_answers`,
`invalid_attachment`, `empty_submission`, `already_graded`,
`no_attachment`, `no_annotated`, `not_released`

**Devices**: `invalid_player_id`, `invalid_platform`, `invalid_role`,
`forbidden_device`

**Parent OTP**: `parent_not_linked`, `invalid_code_format`

---

## 13. Backend issues the app must work around

Found while verifying. None are blockers; all are worth a ticket.

1. `GET /student/subjects/<id>` queries `subjects` while the list queries
   `teacher_classes` — the detail route 404s on ids from the list.
   `mobile_api/__init__.py:811`.
2. `GET /student/enrollments` returns an always-empty `subject_title`: it
   reads `.title` from a `teacher_classes` doc, which stores `name`.
   `mobile_api/__init__.py:892`.
3. `POST /auth/refresh` skips the `token_version` check, so a logged-out
   refresh token still mints an access token — one that is then rejected on
   use. `mobile_api/__init__.py:531`.
4. `POST /notifications/mark-read` with no id silently marks everything read.
   Easy to trigger by accident. `mobile_api/__init__.py:1678`.
5. Drive `embed_url` is an unsigned public link, unchanged per student. See
   §6 and `FLUTTER_APP_PROMPT.md` §4.
6. `MOBILE_API_ENDPOINTS.txt` at the repo root was stale — wrong shapes for
   dashboard, subjects and all notification routes, and missing
   `/auth/social`, `/devices/*` and `/graded.pdf`. This file supersedes it.
