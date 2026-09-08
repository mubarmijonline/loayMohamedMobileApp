# Mobile Videos screen — what the deployed API is missing

Captured 2026-09-07 from the live app against `https://loaymotawie.com`, signed
in as a student enrolled in **Mobile Trial — AS Edexcel**. Every payload below
is a verbatim copy from the client's HTTP log, not a reconstruction.

**Summary:** the mobile app cannot group videos, cannot show posters, and
cannot show a per-class progress pill, because the deployed
`/api/v1/student/content` does not return the fields and
`/api/v1/student/classes` does not exist. The web portal has all of this. The
app already implements the client half and is waiting on the data.

---

## 1. `/api/v1/student/content` is missing four fields

### What the app receives today

```json
{
  "_id": "6a9d80983090dac13e3e3a15",
  "class_id": "6a9d80983090dac13e3e3a14",
  "class_name": "Mobile Trial — AS Edexcel",
  "created_at": "2026-09-06T15:02:48.946000",
  "description": "",
  "duration_seconds": 1326,
  "title": "Quadratics — completing the square",
  "type": "video",
  "watched": false
}
```

### What it needs

| Field | Type | Used for | Present? |
|---|---|---|---|
| `group_title` | string, never null | the section heading. Items with no group must come back as the literal `"(Ungrouped)"` | **no** |
| `order_index` | int | the `#1` / `#2` badge on each card. Per group, not global | **no** |
| `thumbnail_url` | string or null | the card poster | **no** |
| `provider` | `bunny` / `cloudflare` / `drive` / null | player selection | **no** |

### Ordering

The response must be sorted by `(class_id, group_title, order_index,
created_at)` — the same order the portal returns. The app walks the list once
and opens a new section whenever `class_id` or `group_title` changes. It does
not sort client-side, deliberately: sorting is what previously flattened the
grouping.

Worth noting from the capture: **all ten items share the identical
`created_at`** of `2026-09-06T15:02:48.946000`. So `created_at` is not a usable
ordering key on its own — `order_index` is doing the real work and its absence
cannot be worked around.

### Observed result

The app groups by `group_title`, receives none, and correctly falls back to a
single section:

```
Mobile Trial — AS Edexcel
1 group • 10 videos
  (Ungrouped)  [10 videos]
```

The portal, on the same class, renders:

```
Mobile Trial — AS Edexcel                    [6/10 watched]
4 groups • 10 videos
  Algebra [3]  Calculus [3]  Coordinate geometry [2]  Trigonometry [2]
```

"1 group" is correct arithmetic on the input given. No client change can fix
it.

---

## 2. `/api/v1/student/classes` returns 404

```
GET /api/v1/student/classes
→ 404 Not Found
  { "error": "Not found" }
```

Note the body is `{"error": "Not found"}` — a bare string, not the standard
`{ "success": false, "error": { "code", "message" } }` envelope every other
mobile route uses. That suggests it is hitting a generic Flask 404 rather than
a route that exists and is refusing, i.e. the blueprint has no such rule.

This route fills the section header: the class name and the `6/10 watched`
pill. Expected shape:

```json
[{ "_id", "name", "level", "subject", "teacher_name", "cover_url",
   "exam_board", "is_active",
   "homework_total", "homework_done", "quiz_total", "quiz_done",
   "video_total", "video_watched",
   "pending_tasks", "completed_tasks", "total_tasks", "completion_percent" }]
```

The portal already computes all of this for `/api/student/classes`. The app
degrades without it — it falls back to `class_name` from the content rows and
hides the watched pill — so this is lower priority than item 1, but the pill
cannot appear until it exists.

---

## 3. `/api/v1/student/subjects` reports the student as enrolled in nothing

Same session, same student, immediately after `/student/content` returned ten
videos for **Mobile Trial — AS Edexcel**:

```json
{ "counts": { "available": 23, "enrolled": 0, "pending": 0, "total": 23 } }
```

`enrolled: 0` while the student is demonstrably in a class. This is the
`teacher_classes` / `enrollments` id mismatch already reported: the route
compares `teacher_classes._id` against `enrollments.subject_id`, and those
point at two different collections that never share ids, so `is_enrolled` is
permanently false and `filter=enrolled` permanently returns `[]`.

Consequence for this screen: the app cannot use `/student/subjects` to decide
which classes are the student's. It uses `/student/dashboard`'s `classes`
array instead, which is correct because that route resolves through
`class_students.class_id → teacher_classes._id`.

Mentioned here because it is the same root cause and worth fixing in the same
pass.

---

## The pattern

Routes built on `_get_student_class_ids` (`class_students.class_id →
teacher_classes._id`) work: `/student/dashboard`, `/student/content`,
`/student/assignments`, `/watch-heartbeat`.

Routes that reach for the `enrollments` or `subjects` collections do not:
`/student/subjects` flags, `/student/subjects/<id>`, `/student/enrollments`
titles, `/student/subjects/<id>/lessons`.

`/student/content` is in the first group and works — it simply is not
projecting the four fields the portal's equivalent projects.

---

## What to change

1. Add `group_title` (defaulting to the literal `"(Ungrouped)"`),
   `order_index`, `thumbnail_url` and `provider` to the `/student/content`
   projection.
2. Sort by `(class_id, group_title, order_index, created_at)`.
3. Add `/student/classes`, mirroring the portal's `/api/student/classes`.

The portal already does all three. If a fix exists on an unmerged branch, the
shortest path is to ship that rather than rewrite it.

## How to verify, before touching the app

```bash
curl -s -H "Authorization: Bearer <student token>" \
  https://loaymotawie.com/api/v1/student/content | head -c 400
```

`group_title` must appear. Then:

```bash
curl -s -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer <token>" \
  https://loaymotawie.com/api/v1/student/classes
```

Must be `200`.

Once both pass, the app groups correctly with **no client change** — the
grouping, the `#n` badges, the posters and the watched pill are already
implemented and covered by 13 unit tests. The screen currently reads
"1 group • 10 videos" only because that is the honest answer for the data it
is given.
