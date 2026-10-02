# Parent sign-in for App Review

Apple has now rejected the app twice under guideline 2.1 because they cannot
sign in as a parent. Checked 2026-10-02 against production:

```
POST /api/v1/auth/parent/otp/request  {"phone":"+12025550124"}
200 {"success":true,"data":{"otp_sent":true,"expires_in":300,
     "resend_after":60,"linked_students":1}}
```

So the review parent number is linked to the review student and the server
sends a code — by SMS, to a number reserved for fiction that no handset can
receive. App Review typed what the notes gave them and saw "Incorrect
verification code" (their screenshot, review of 29 September, iPad Air 11-inch).

Nothing is wrong in the app: it sends the same phone string on request and on
verify. The server needs one fixed code for that one number.

---

## Prompt for your backend developer

~~~markdown
Apple's reviewers cannot sign in to the parent side of our app, and have
rejected the submission twice for it (guideline 2.1). They cannot receive an
SMS, so the one-time code never reaches them. Please add a fixed code for a
single review phone number.

Two settings, in the environment (never in git):

    REVIEW_PARENT_PHONE=+12025550124
    REVIEW_PARENT_OTP=<any six digits, e.g. 314159>

Behaviour:

1. `POST /api/v1/auth/parent/otp/request` — when the requested phone matches
   REVIEW_PARENT_PHONE, do not send an SMS, and return the normal success
   envelope unchanged: `{"otp_sent":true,"expires_in":300,"resend_after":60,
   "linked_students":N}`. The app must behave exactly as it does today.

2. `POST /api/v1/auth/parent/otp/verify` — for that number, accept exactly
   REVIEW_PARENT_OTP and nothing else, ignoring expiry and attempt counters,
   and return the same payload a real parent login returns: user object with
   `role: "parent"`, access and refresh tokens, and `linked_students`. The
   session must be an ordinary parent session afterwards.

3. Compare phone numbers after normalising: strip spaces, dashes, brackets and
   a leading `00`, then compare in E.164. The app sends `+12025550124`, but a
   reviewer may type it with spaces.

4. The bypass applies only when both settings are present and non-empty, and
   only to that one number. With either unset, behave exactly as today. Never
   accept a wildcard or a prefix.

5. Do not rate-limit or lock out that number: reviewers retry.

6. Log each use (number, timestamp, IP) at info level, so we can see when App
   Review signs in. Never log the code itself.

7. Keep the review parent linked to the review student that
   `seed-review-account` creates, so the portal has a child with content.
   Re-running the seed must keep the link.

Checks to run and send back (replace CODE with the six digits):

```bash
BASE=https://loaymotawie.com/api/v1/auth/parent/otp

# 1. Request: 200, otp_sent true, and no SMS leaves the system
curl -s -X POST $BASE/request -H 'Content-Type: application/json' \
  -d '{"phone":"+12025550124"}'

# 2. Verify with the fixed code: 200 with tokens and linked_students
curl -s -X POST $BASE/verify -H 'Content-Type: application/json' \
  -d '{"phone":"+12025550124","code":"CODE"}'

# 3. Wrong code for the same number still fails: 401 otp_invalid
curl -s -X POST $BASE/verify -H 'Content-Type: application/json' \
  -d '{"phone":"+12025550124","code":"000000"}'

# 4. A real parent number must NOT accept the fixed code: 401
curl -s -X POST $BASE/verify -H 'Content-Type: application/json' \
  -d '{"phone":"+20XXXXXXXXXX","code":"CODE"}'
```

Send me: confirmation that it is live, the six digits privately (not in a
repository, not in chat), and the output of checks 2, 3 and 4. I enter the code
in App Store Connect myself.
~~~

---

## After it is live

1. Sign in on TestFlight: Parent tab, +1 202 555 0124, the six digits. The
   parent portal should list the review student.
2. App Store Connect → App Review Information → Notes: replace the blank in
   the parent line with the real code.
3. Reply in Resolution Center and submit the same build again. A guideline 2.1
   rejection does not need a new binary.
4. After approval, the code can stay or be rotated; if it changes, update the
   notes before the next submission, because Apple reviews every update with
   these credentials.
