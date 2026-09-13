# Backend work for the App Store and Google Play launch

Checked 2026-09-13 against `https://loaymotawie.com`, without signing in:

| What the stores need | Live today |
|---|---|
| `POST /api/v1/auth/account/delete` | `404`: not built |
| `https://loaymotawie.com/delete-account` | `404` |
| `https://loaymotawie.com/privacy` | `404` |
| `https://loaymotawie.com/contact` (the Support URL) | `200` ✅ |

Items 1–4 of the prompt block both store submissions. Items 5–7 do not, but
reviewers will run into them.

**What you send with it:** the prompt below, and
`docs/store/PRIVACY_POLICY_DRAFT.md` as an attachment.

**What stays with you, not the developer:** your legal name, the policy's
effective date and the contact email for the privacy page; and the review
account's password, which you type into App Store Connect and Play Console
yourself.

This supersedes the prompts in `BACKEND_ACCOUNT_DELETION.md` and
`BACKEND_VIDEO_STREAMING.md`, which remain the long-form reference.

---

## Prompt for your backend developer

~~~markdown
We are submitting the **Loay Motawie** student app (Flutter; bundle id
`com.loaymohamed.app` on iOS and Android) to the App Store and Google Play. It
uses our API at `https://loaymotawie.com/api/v1`. Apple and Google will both
reject it until items 1–4 below are live in production. Items 5–7 don't block
submission, but reviewers will see them. Please work in this order, and reply
with the check results listed under each item.

## 1. Account deletion endpoint (blocks both stores)

Apple guideline 5.1.1(v) and Google Play's account deletion policy: an app with
in-app sign-up must let people delete their account from inside the app. The
app already has the button and is built against exactly this contract.

`POST /api/v1/auth/account/delete`. Bearer access token, student or parent
(the same auth as `GET /auth/me`).

- Body when the account has a password (`has_password: true`):
  `{"password": "<current password>"}`
- Body when it doesn't: `{"confirm": "DELETE"}`
- Success, `200`: `{"success": true, "data": {"deleted": true}}`
- Errors, in the standard envelope:
  - `400 password_required`: the account has a password and none was sent
  - `400 invalid_current_password`: wrong password
  - `400 confirmation_required`: no password on the account, and `confirm` is
    not exactly `DELETE`
  - `401`: token problems only (missing, expired, revoked)
  - `429`: optional rate limit

**A wrong password must be `400`, never `401`.** The app treats every 401 as a
session problem: it refreshes, retries, then signs the student out.

Before answering `200`, in one operation:

1. Revoke every session: bump `token_version`. Also make `POST /auth/refresh`
   check `token_version`. Today it doesn't (`mobile_api/__init__.py:531`), so a
   deleted or logged-out user's refresh token still mints access tokens.
2. Delete the account's push-device registrations (what `/devices/register`
   stored). The app can't unregister its own device in this flow.
3. Delete the personal data: name, email, phone, parent phone, school, grade,
   avatar, password hash, `apple_user_id`, `apple_email_relay`, `auth_methods`.
   If you store Sign in with Apple refresh tokens for older accounts, revoke
   them with Apple's `/auth/revoke`.
4. Delete the account's stored files: the avatar and homework attachments.
5. Delete or anonymise the academic records (submissions, grades, watch
   history). Tell me which you chose: the privacy policy has to say the same.

Keep returning `has_password` in the user object from `/auth/login` and
`/auth/me`. The app uses it to choose between asking for the password and
asking the student to type DELETE.

Checks. Use a throwaway test account, never a real student:

```bash
# The route exists: expect 401, not 404
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  https://loaymotawie.com/api/v1/auth/account/delete

# Wrong password: expect 400 invalid_current_password, and nothing deleted
curl -s -X POST -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"password":"wrong"}' \
  https://loaymotawie.com/api/v1/auth/account/delete

# After a real deletion, both of these must be 401
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer $TOKEN" https://loaymotawie.com/api/v1/auth/me
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  -H 'Content-Type: application/json' -d "{\"refresh_token\":\"$REFRESH\"}" \
  https://loaymotawie.com/api/v1/auth/refresh
```

## 2. Account deletion web page (blocks Google Play)

Google's Data safety form needs a URL where someone can delete their account
**without the app installed**: `https://loaymotawie.com/delete-account`.

- Publicly viewable, and names the app: "Loay Motawie".
- Lets the person sign in and delete the account (call the same service
  function as item 1), or send a request by email or phone that you act on
  within a stated number of days.
- Says what is deleted, what is kept (if anything) and for how long.
- Linked from the site footer.

## 3. Privacy policy page (blocks both stores)

Publish the attached `PRIVACY_POLICY_DRAFT.md` at
`https://loaymotawie.com/privacy`: public, no login, plain HTML, linked from the
site footer. From build 1.0.5 (10) the app opens this exact URL from the
sign-in screen, the student Profile and the parent home, and it is the URL
entered in both store consoles, so it must never move.

- Fill in `[Hosting provider]`, and the deletion timing, so they match what
  item 1 actually does.
- Remove the bullet about screenshot and screen-recording records: the server
  doesn't receive them (item 8 would change that).
- Leave `[LEGAL NAME]`, `[DATE]` and `[CONTACT EMAIL]` for me to supply.

## 4. App Review accounts (blocks both stores)

Apple and Google sign in with an account we give them, and Apple uses it again
for every update. Add an idempotent management command, for example
`flask seed-review-account`, that creates the following, or restores it if it
already exists:

- **A student used only for review.** A made-up name ("App Review") and a phone
  number that isn't a real person's: the video watermark shows both. Email
  login, and a strong password. Print the password once in the terminal and
  give it to me privately. Never commit it or put it in a seed file.
- Every profile field filled in, `must_change_password: false`, email and phone
  verified, `is_active: true`, so the app goes straight to Home without showing
  Complete Profile or Change Password.
- Enrolled in a class with at least 3 lesson videos in 2 groups (with
  thumbnails and `order_index`, and actually playable), 1 open homework, 1
  homework already graded with feedback and the grade released, 1 quiz, and 3
  or more notifications.
- Reviewers test account deletion, so running the command again must rebuild
  the whole account. We will run it before every submission.
- Nothing may block this account: no device cap, no single-session rule
  (Apple may sign in on an iPhone and an iPad at once), no country or IP
  restriction (Apple reviews from the US), and no OTP step.
- Recommended: **a review parent.** One phone number, linked to the review
  student, that accepts a fixed OTP code without sending an SMS. Only that one
  number, and log every use. Without it, the parent sign-in can't be reviewed.

## 5. Video start-up speed (reviewers must be able to play a lesson)

`GET /api/v1/student/content/<id>/drive-stream` proxies Google Drive. Students
wait several seconds before a video starts, and again on every seek. The
phones' players (AVPlayer, ExoPlayer) use HTTP Range requests: `bytes=0-1`
first, then the ranges they need, then a new range for each seek.

1. Measure the time to first byte for `Range: bytes=0-1` and for a range near
   the end of the file. Target: under 300 ms each.
2. Stream the requested range: forward the client's `Range` header to Drive,
   and answer `206` with `Content-Range`, `Content-Length` and
   `Accept-Ranges: bytes`. Never download the whole file first.
3. Cache the Google access token (it lasts about an hour) and each file's size
   and MIME type, and reuse one keep-alive HTTP session to Google.
4. Turn off nginx buffering for this route (`proxy_buffering off;`, or the
   `X-Accel-Buffering: no` response header).
5. Make sure every MP4 has its `moov` atom at the front:
   `ffmpeg -i in.mp4 -c copy -movflags +faststart out.mp4` (lossless, seconds
   per file).
6. A streaming response holds a worker for the whole lesson: use gevent
   workers, or many more sync workers.
7. Longer term, move lessons to Bunny Stream or Cloudflare Stream. The app
   already plays both when `/embed` returns `provider: "bunny"` or
   `"cloudflare"`, with no app update.

## 6. Lesson counts

Add `lessons_count` (how many content items the student can see in that
class) to each class in `GET /student/dashboard` → `classes[]` and in
`GET /student/classes`. Build 10 counts on the device for now, but the server
knows the true number.

## 7. Data bugs found earlier: fix, or confirm they're fixed

Most come from mobile routes that look up `enrollments`/`subjects` instead of
`class_students`/`teacher_classes`. The portal's `_get_student_class_ids`
helper is the correct pattern.

- `GET /student/subjects/<id>/lessons` can never succeed: 403 or 410
  (`mobile_api/__init__.py:872`).
- `GET /student/subjects?filter=enrolled` is always empty, and `is_enrolled`
  is always false (`:729`).
- `GET /student/subjects/<id>` reads the wrong collection, so ids from the list
  404 (`:811`).
- `GET /student/enrollments` returns an empty `subject_title`, because
  `teacher_classes` stores it as `name` (`:892`).
- `POST /notifications/mark-read` with no id marks everything read (`:1678`).
- Confirm that a `POST /student/enrollment-requests` made with a
  `teacher_classes` id can be approved into an active enrolment.

## 8. Later, not before the stores approve the app

- `POST /api/v1/student/capture-events`, to store the screenshot and
  screen-recording reports the app keeps on the device today. Body
  `{"events":[{"event":"screenshot"|"recording_started"|"external_display","content_id":"<id or null>","at":"<ISO-8601 UTC>","platform":"ios"|"android"}]}`,
  response `200 {"recorded": <n>}`. The app needs an update to start sending
  them, and the privacy policy bullet from item 3 comes back.
- A device cap on `/student/content/<id>/embed`, keyed on the `device_id` the
  app sends to `/devices/register`. Exempt the review accounts.
- Append `&share=false&sharing=false&pip=false` to Bunny embed URLs in
  `/embed` (the app adds them itself today).

When you're done, send me: the check output from item 1, the two URLs from
items 2 and 3, confirmation that the review account seeds (without the
password), and the before and after timings from item 5.
~~~
