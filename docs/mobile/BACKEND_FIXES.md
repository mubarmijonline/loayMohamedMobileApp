# Backend defects affecting the Flutter student app

Updated 2026-09-06 after backend review. Items 1 and 2 were **confirmed from
source by the backend team**, not inferred from the client. Line references are
to `backend/app/blueprints/`.

The app now works around every item below. The workarounds are in place and
tested, so nothing here blocks a release. Each one is a real defect that will
keep costing correctness until it is fixed.

## The pattern behind items 1, 2 and 3

The mobile API has one helper that resolves a student's classes correctly,
`_get_student_class_ids` at `mobile_api/__init__.py:199`, which walks
`class_students.class_id` to `teacher_classes._id`. It is the same helper the
web portal uses at `student_v2/__init__.py:47`.

**Every mobile route built on that helper works**: `/student/dashboard`,
`/student/content`, `/student/assignments`, `/watch-heartbeat`.

**Every mobile route that reaches for the `enrollments` or `subjects`
collections is broken**, because `enrollments.subject_id` points at `subjects`
while the class documents live in `teacher_classes`, and those two collections
never share ids.

Fixing the pattern once fixes items 1, 2 and 3 together.

---

## 1. CONFIRMED — `GET /student/subjects/<id>/lessons` cannot succeed for any input

`mobile_api/__init__.py:872` takes one oid and checks it against two
collections that never share ids:

```python
subject    = db.teacher_classes.find_one({"_id": oid})              # teacher_classes id
enrollment = db.enrollments.find_one({"subject_id": oid, ...})      # subjects id
```

Pass a `teacher_classes` id and the first lookup succeeds while the enrollment
lookup misses, giving `403 not_enrolled`. Pass a `subjects` id and the first
lookup misses, giving `410 subject_closed`. There is no third input.

**Client workaround (shipped):** the app no longer calls this route at all.
Lesson content is read from `GET /student/content`, which resolves classes
through the working helper. `lessonsProvider` is marked `@Deprecated` so the
breakage stays documented at the call site.

**Fix:** resolve enrollment through `class_students`, matching the portal.

**Acceptance:** for a student enrolled in one class, passing that class's `_id`
returns its lessons with 200.

---

## 2. CONFIRMED — `filter=enrolled` is permanently empty and the enrollment flags are constants

`mobile_api/__init__.py:729` compares ids across the same two collections:

```python
docs        = db.teacher_classes.find(query)                        # teacher_classes ids
enrolled_ids = {e["subject_id"] for e in db.enrollments...}          # subjects ids
is_enrolled  = sub_oid in enrolled_ids                               # never true
```

So `is_enrolled` is permanently `false`, `enrollment_status` permanently
`"none"`, `counts.enrolled` permanently `0`, and `filter=enrolled` returns
`[]`. `filter=available` returns everything.

These are not unreliable values. They are constants, and no client can
distinguish them from a student who genuinely has no enrollments.

**Client workaround (shipped):** the app builds its "my subjects" view from
`GET /student/dashboard`'s `classes` array only, and treats
`GET /student/subjects` as a browse-only catalogue whose `is_enrolled` and
`enrollment_status` fields are ignored entirely.

**Fix:** as item 1.

**Acceptance:** a student enrolled in exactly one class gets one row from
`filter=enrolled`, with `enrollment_status: "active"` and `counts.enrolled: 1`.

---

## 3. `GET /student/subjects/<id>` queries the wrong collection

`mobile_api/__init__.py:811`. The list route reads `teacher_classes`; the
detail route reads `subjects`. An `_id` from the list always 404s here.

**Client workaround (shipped):** detail is reconstructed from the list object.

---

## 4. `GET /student/enrollments` returns an always-empty `subject_title`

`mobile_api/__init__.py:892` reads `.title` from a `teacher_classes` document.
Those store the name under `name`.

**Fix:** read `name`, or return both keys during a transition.

---

## 5. OPEN QUESTION — does `POST /student/enrollment-requests` actually resolve?

The app now shows a "Request enrollment" button when a student opens a subject
that is not one of their classes. Backend review says the POST still works and
only the read-back flags lie.

Given items 1 and 2, please confirm which id that route writes into
`enrollments.subject_id`, and that a request created from a
`teacher_classes` id (the only id the client has) can actually be approved into
an active enrollment.

If it cannot, the button sends students into a void and we should remove it
rather than leave it looking functional.

---

## 6. Google Drive video URLs are unsigned, permanent and identical for every student

`mobile_api/__init__.py:946-958` and `1140-1168`. When a content item has
`drive_file_id`, `/student/content/<id>/embed` returns
`https://drive.google.com/file/d/<id>/preview`.

That URL is bearer-free. Obtaining it needs a valid token; using it does not.
Paste it into any browser, on any device, and it plays. Nothing expires it and
nothing ties it to the student who fetched it.

This is the single change that decides whether the client-side playback
lockdown is real or decorative. The portal already routes Bunny through a
server-side player with sharing disabled and the signed URL never leaving the
origin. Moving Drive content to Bunny reuses machinery that exists and works.

**Recommendation:** migrate Drive content to Bunny. Failing that, proxy it
behind a token-authenticated streaming route. Failing both, confirm in writing
that every Drive file has *"Viewers and commenters can download, print, and
copy"* turned off, as part of the upload checklist.

---

## 7. Bunny embed URLs ship without the share-disabling parameters

The portal appends `&share=false&sharing=false&pip=false` server-side
(`api.py:632`). The mobile `/embed` route returns the bare signed URL, so
Bunny renders a share button, a copy-link affordance and picture-in-picture
inside a player whose entire purpose is that the video cannot leave the app.

**Client workaround (shipped):** the Flutter player appends the three
parameters itself before loading, preserving the signed `token` and `expires`.
Covered by tests.

**Fix:** append them in `/embed` so web and mobile cannot drift, and so a
future client cannot forget.

---

## 8. No device limit on mobile

The portal caps a student at 2 devices, fingerprinted on UA plus IP, before
releasing any embed URL (`student_v2/__init__.py:60`). The mobile API releases
embed URLs to any valid token, with no cap.

A shared login is therefore capped on web and unlimited on mobile, which makes
mobile the obvious way to share an account. This cannot be enforced client
side: the client is the thing being shared.

**Ask:** apply the same cap in `/student/content/<id>/embed`, keyed on the
device id the app already sends to `/devices/register`.

---

## 9. No endpoint to report a screen capture

Still absent. iOS cannot block a screenshot; it can only be detected after the
fact. The app detects screenshots, recordings and external displays, attributes
them to the student and the content, and queues them locally, where they stay.

Suggested shape, consistent with the existing envelope:

```
POST /api/v1/student/capture-events        (Bearer, student)
Body: { "events": [ {
          "event": "screenshot" | "recording_started" | "external_display",
          "content_id": "<oid|null>",
          "at": "<ISO-8601 UTC>",
          "platform": "ios" | "android"
        } ] }
200: { "recorded": <int> }
```

Batched, because events are queued offline. Duplicates are acceptable; dropped
events are not.

---

## Confirmed working, no action needed

- `expires_in` and `refresh_expires_in` are returned by register, login, social
  and refresh (`mobile_api/__init__.py:377`). The client's proactive refresh at
  80% of the access token's life is correctly fed.
- The mark is under `grade`, not `score` (`student_view.py:39`). The client
  reads `grade` and shows nothing when `released` is false.
