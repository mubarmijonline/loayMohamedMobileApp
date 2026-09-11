# Account deletion — required by both stores, not implemented

Checked 2026-09-11 against `https://loaymotawie.com`. Neither store will accept
the app without this, and the app cannot offer it until a backend route exists.

## Why this blocks release

- **Apple, Guideline 5.1.1(v):** an app that lets people create an account
  must let them delete it *from inside the app*. Deactivating it, or telling
  them to email support, does not count.
- **Google Play, account deletion policy:** the same in-app requirement, plus a
  web page where someone can request deletion *without* the app installed. Its
  URL goes in the Data safety form.

The app has in-app sign-up (`POST /auth/register`, the "Create one" link on the
login screen), so both apply.

## Evidence that no route exists

Unauthenticated requests. A `401` would mean the route exists and wants a token.

| Request | Status |
|---|---|
| `DELETE /api/v1/auth/me` | `405` — `/auth/me` exists, GET only |
| `POST /api/v1/auth/me` | `405` |
| `DELETE` and `POST /api/v1/auth/account` | `404` |
| `DELETE` and `POST /api/v1/student/account` | `404` |
| `DELETE` and `POST /api/v1/auth/delete-account` | `404` |

API_BRIEF §12 lists every error code the backend emits. None relates to deletion.

## The contract the app is built against

### `POST /api/v1/auth/account/delete`

Auth: student **or** parent, like `/auth/me`. POST rather than `DELETE` because
the request carries a body, and some proxies drop bodies on `DELETE`.

For an account with a password (`has_password: true`):

```json
{ "password": "<current password>" }
```

For an account without one (`has_password: false` — the legacy Google/Apple
sign-ups):

```json
{ "confirm": "DELETE" }
```

Success — `200`:

```json
{ "success": true, "data": { "deleted": true } }
```

Errors, in the standard envelope:

| Status | `error.code` | When |
|---|---|---|
| `400` | `password_required` | The account has a password and none was sent |
| `400` | `invalid_current_password` | Wrong password (reuses the existing code) |
| `400` | `confirmation_required` | No password on the account, and `confirm` is not exactly `DELETE` |
| `401` | the usual token codes | Missing, expired or revoked token |
| `429` | — | Optional: too many attempts, if login is rate-limited |

**A wrong password must be `400`, never `401`.** The app treats every `401` as a
session problem: it refreshes the token and retries, and on some codes signs the
user out. A `401` here would log out a student who mistyped their password
instead of letting them try again.

## What the deletion has to do

In one operation, before responding `200`:

1. **Revoke every session**, as logout does (bump `token_version`).
2. **Delete the account's push-device registrations.** The app normally
   unregisters its own device before logging out, but it cannot here: until the
   server answers, the password might be wrong, and once it answers the token is
   already dead. So the server has to do it.
3. **Delete personal data:** name, email, phone, parent phone, school, grade,
   avatar image, password hash, `apple_user_id`, `apple_email_relay`,
   `auth_methods`.
4. **Delete uploaded files:** the avatar and submission attachments in storage.
5. **Academic records** (submissions, grades, watch history): delete them, or
   detach them from the person if a teacher genuinely needs the aggregate.
   Apple only allows keeping data where there is a legal reason. Whichever you
   choose, the privacy policy has to say so.

Delete immediately. A grace period is allowed, but then the app has to tell the
student when deletion will happen — more to build and more to explain.

## The web page Google requires

A page at a stable URL — `https://loaymotawie.com/delete-account` is the obvious
one — where someone can sign in and delete their account, or submit a request
that you then act on. It has to name the app, say what is deleted and what (if
anything) is kept, and say how long it takes. Today that path returns `404`.

## Parents

`parent_not_linked` (§12) suggests the parent OTP flow only admits phone numbers
a school has already linked. That would mean parents never *create* an account
in the app, so the rule does not strictly apply to them — please confirm. Either
way, make the route work for any authenticated role; it costs nothing and avoids
a second route later.

## How to verify

```bash
# 1. The route exists (expect 401, not 404):
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  https://loaymotawie.com/api/v1/auth/account/delete

# 2. A wrong password is a 400 with the right code, and changes nothing:
curl -s -X POST -H "Authorization: Bearer <token of a TEST account>" \
  -H 'Content-Type: application/json' -d '{"password":"wrong"}' \
  https://loaymotawie.com/api/v1/auth/account/delete
# -> 400 {"success":false,"error":{"code":"invalid_current_password",...}}

# 3. After a real deletion, the same token is rejected:
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "Authorization: Bearer <same token>" https://loaymotawie.com/api/v1/auth/me
# -> 401
```

Use a throwaway test account for steps 2 and 3, never a real student.

## Client status

The app side is built against this contract: a **Delete account** entry on the
profile screen, confirmation by password (or by typing `DELETE` for accounts
without one), and sign-out with a notice once the server confirms.

**Do not submit to either store until this route is live.** A reviewer who taps
Delete account and gets an error is rejected under the same guideline as having
no button at all.
