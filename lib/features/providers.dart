import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '_shared/models.dart';
import 'auth/presentation/auth_controller.dart';
import 'student_repository.dart';

final studentRepositoryProvider = Provider<StudentRepository>(
  (ref) => StudentRepository(ref.read(apiClientProvider)),
);

/// Combines the dashboard summary with the subjects list so the Home screen
/// always has a populated subjects feed even when the backend's dashboard
/// payload omits them.
final dashboardProvider = FutureProvider<StudentDashboard>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  // `/student/subjects` and `/student/enrollments` are deliberately NOT
  // fetched here. The first is a browse catalogue that must never reach this
  // screen, and the second is empty for everyone (BACKEND_FIXES.md item 4).
  // Requesting them cost two round trips per dashboard load and existed only
  // to feed fallbacks that produced wrong answers.
  final results = await Future.wait([
    repo.dashboard().then<Object?>((v) => v).catchError((_) => null),
    repo.quizzes().then<Object?>((v) => v).catchError((_) => <Assignment>[]),
    repo
        .assignments(type: 'homework')
        .then<Object?>((v) => v)
        .catchError((_) => <Assignment>[]),
    repo.contents().then<Object?>((v) => v).catchError((_) => <ContentItem>[]),
  ]);

  final dash = results[0] as StudentDashboard?;
  final quizzes = (results[1] as List<Assignment>? ?? const <Assignment>[]);
  final homework = (results[2] as List<Assignment>? ?? const <Assignment>[]);
  final contents = (results[3] as List<ContentItem>? ?? const <ContentItem>[]);

  // The enrolled-subjects list is `/student/dashboard`'s `classes` array, and
  // nothing else.
  //
  // There is no fallback, deliberately. This used to end with
  // `subjects = subs` — the unfiltered `/student/subjects` catalogue — so a
  // student enrolled in nothing was shown all 22 subjects in the system as
  // "Your subjects", each of which then failed on open. Verified against a
  // live response on 2026-09-06: `classes: []`, `enrollments: []`, and the
  // screen still listed 22.
  //
  // The intersect-with-enrollments branch was also removed. It could never
  // match: `enrollments.subject_id` refers to the `subjects` collection while
  // `Subject.id` comes from `teacher_classes`, and those never share ids
  // (BACKEND_FIXES.md items 1 and 2). It only ever fell through to `subs`,
  // which is how the catalogue leaked.
  //
  // An empty list is the correct answer for a student with no enrollments.
  // Do not add a fallback here; `subs` is a browse catalogue, not a roster.
  final subjects = dash?.subjects ?? const <Subject>[];
  // The "Subjects" tile counts the same list rendered below it, so the two
  // can never disagree.
  final enrolledCount = subjects.length;
  final quizCount = quizzes.length;
  final assignmentCount = homework.length;
  final overall = subjects.isEmpty
      ? 0.0
      : subjects
              .map((s) => s.completionPercent ?? 0)
              .fold<double>(0, (a, b) => a + b) /
          subjects.length;

  return StudentDashboard(
    subjects: subjects,
    overallCompletion:
        dash?.overallCompletion == null || dash!.overallCompletion == 0
            ? overall
            : dash.overallCompletion,
    totalWatchedSeconds: dash?.totalWatchedSeconds ?? 0,
    pendingAssignments: homework
        .where((a) => a.status != 'submitted' && a.status != 'graded')
        .length,
    pendingQuizzes: quizzes
        .where((a) => a.status != 'submitted' && a.status != 'graded')
        .length,
    unreadNotifications: dash?.unreadNotifications ?? 0,
    enrolledCount: enrolledCount,
    quizCount: quizCount,
    assignmentCount: assignmentCount,
    contentCount: contents.length,
  );
});

final subjectsProvider = FutureProvider<List<Subject>>(
  (ref) => ref.read(studentRepositoryProvider).subjects(),
);

/// The subjects this student is enrolled in.
///
/// Built from `GET /student/dashboard`'s `classes` array, and ONLY from there.
///
/// `GET /student/subjects` cannot be used for this. Backend confirmed
/// 2026-09-06 (`mobile_api/__init__.py:729`) that the route compares
/// `teacher_classes._id` against `enrollments.subject_id`, and those point at
/// two different collections that never share ids. The consequence is that
/// `is_enrolled` is permanently false, `enrollment_status` is permanently
/// "none", `counts.enrolled` is permanently 0, and `filter=enrolled` returns
/// an empty list. The flags are not unreliable; they are constant.
///
/// The dashboard route works because it resolves classes through
/// `class_students.class_id -> teacher_classes._id` (`:199`), the same helper
/// the web portal uses everywhere. Every mobile route built on that helper is
/// sound; every route that reaches for `enrollments` or `subjects` is not.
///
/// Do not "improve" this by consulting `/student/subjects` — it briefly did,
/// and the two failure modes were showing the entire catalogue as enrolled
/// (when the flags defaulted open) and showing nothing at all (when the
/// filter was trusted).
final enrolledSubjectsProvider = FutureProvider<List<Subject>>((ref) async {
  final dashboard = await ref.read(dashboardProvider.future).catchError(
        (_) => const StudentDashboard(subjects: [], overallCompletion: 0),
      );
  return dashboard.subjects;
});

/// True when [subjectId] is one of the student's own classes.
///
/// The only trustworthy enrollment signal available to the client, for the
/// reasons above.
final isEnrolledInProvider = Provider.family<bool, String>((ref, subjectId) {
  final mine = ref.watch(enrolledSubjectsProvider).valueOrNull ?? const [];
  return mine.any((s) => s.id == subjectId || s.classId == subjectId);
});

final subjectProvider = FutureProvider.family<Subject, String>(
  (ref, id) => ref.read(studentRepositoryProvider).subject(id),
);

/// Best-effort name resolver: if the detail endpoint returns an empty/blank
/// name we fall back to the enrolled/all subjects lists which always carry it.
final subjectNameProvider = Provider.family<String?, String>((ref, id) {
  final detail = ref.watch(subjectProvider(id)).valueOrNull;
  if (detail != null && detail.name.trim().isNotEmpty) return detail.name;
  final enrolled = ref.watch(enrolledSubjectsProvider).valueOrNull ?? const [];
  for (final s in enrolled) {
    if (s.id == id && s.name.trim().isNotEmpty) return s.name;
  }
  final all = ref.watch(subjectsProvider).valueOrNull ?? const [];
  for (final s in all) {
    if (s.id == id && s.name.trim().isNotEmpty) return s.name;
  }
  return null;
});

/// `GET /student/subjects/<id>/lessons`.
///
/// **This route cannot succeed for any input.** Backend confirmed 2026-09-06
/// (`mobile_api/__init__.py:872`) that it takes one id and checks it against
/// two collections that never share ids:
///
///   * `teacher_classes.find_one({_id: oid})`      -> a teacher_classes id
///   * `enrollments.find_one({subject_id: oid})`   -> a subjects id
///
/// Pass a class id and the enrollment lookup misses: `403 not_enrolled`. Pass
/// a subject id and the first lookup misses: `410 subject_closed`. There is no
/// third option.
///
/// Nothing in the app calls this. Lesson content comes from
/// `GET /student/content`, which resolves classes through the helper that
/// works. Kept only so the breakage stays documented at the call site rather
/// than being rediscovered.
@Deprecated(
  'Broken server-side: /lessons checks one id against two collections and can '
  'never return lessons. Use contentsProvider instead. See '
  'docs/mobile/BACKEND_FIXES.md.',
)
final lessonsProvider = FutureProvider.family<List<Lesson>, String>(
  (ref, subjectId) => ref.read(studentRepositoryProvider).lessons(subjectId),
);

/// `GET /student/classes` — the Videos screen headers.
final studentClassesProvider = FutureProvider<List<StudentClass>>(
  (ref) => ref.read(studentRepositoryProvider).classes(),
);

/// `/student/content`, grouped the way the portal groups it.
///
/// The grouping is done here rather than in a widget so the ordering rule
/// lives in one place and is unit-testable.
final contentSectionsProvider =
    FutureProvider<List<ContentSection>>((ref) async {
  final items = await ref.watch(contentsProvider.future);
  // Headers are a nicety; a failure to load them must not empty the screen.
  final classes = await ref
      .watch(studentClassesProvider.future)
      .catchError((_) => <StudentClass>[]);
  return ContentSection.group(items, classes: classes);
});

/// Thumbnail bytes for one content item, fetched with the auth header.
final contentThumbnailProvider =
    FutureProvider.family<Uint8List?, String>((ref, contentId) {
  return ref.read(studentRepositoryProvider).contentThumbnail(contentId);
});

final enrollmentsProvider = FutureProvider<List<Enrollment>>(
  (ref) => ref.read(studentRepositoryProvider).enrollments(),
);

final progressProvider = FutureProvider.family<SubjectProgress, String>(
  (ref, id) => ref.read(studentRepositoryProvider).progress(id),
);

final assignmentsProvider = FutureProvider.family<List<Assignment>, String?>(
  (ref, type) => ref.read(studentRepositoryProvider).assignments(type: type),
);

final assignmentProvider = FutureProvider.family<Assignment, String>(
  (ref, id) => ref.read(studentRepositoryProvider).assignment(id),
);

final quizzesProvider = FutureProvider<List<Assignment>>(
  (ref) => ref.read(studentRepositoryProvider).quizzes(),
);

/// Per-subject workload counters, derived from the homework + quizzes feeds.
class SubjectWorkload {
  const SubjectWorkload({
    this.assignmentsTotal = 0,
    this.assignmentsPending = 0,
    this.quizzesTotal = 0,
    this.quizzesPending = 0,
  });
  final int assignmentsTotal;
  final int assignmentsPending;
  final int quizzesTotal;
  final int quizzesPending;

  int get pendingTotal => assignmentsPending + quizzesPending;
  int get grandTotal => assignmentsTotal + quizzesTotal;
}

final subjectWorkloadProvider =
    FutureProvider<Map<String, SubjectWorkload>>((ref) async {
  final repo = ref.read(studentRepositoryProvider);
  final results = await Future.wait([
    repo.assignments(type: 'homework').catchError((_) => <Assignment>[]),
    repo.quizzes().catchError((_) => <Assignment>[]),
  ]);
  final homework = results[0];
  final quizzes = results[1];

  bool isPending(Assignment a) =>
      a.status != 'submitted' && a.status != 'graded';

  final acc = <String, _MutableWorkload>{};
  for (final a in homework) {
    final id = a.subjectId ?? '';
    if (id.isEmpty) continue;
    final w = acc.putIfAbsent(id, _MutableWorkload.new);
    w.aTotal++;
    if (isPending(a)) w.aPending++;
  }
  for (final q in quizzes) {
    final id = q.subjectId ?? '';
    if (id.isEmpty) continue;
    final w = acc.putIfAbsent(id, _MutableWorkload.new);
    w.qTotal++;
    if (isPending(q)) w.qPending++;
  }
  return acc.map(
    (k, v) => MapEntry(
      k,
      SubjectWorkload(
        assignmentsTotal: v.aTotal,
        assignmentsPending: v.aPending,
        quizzesTotal: v.qTotal,
        quizzesPending: v.qPending,
      ),
    ),
  );
});

class _MutableWorkload {
  int aTotal = 0;
  int aPending = 0;
  int qTotal = 0;
  int qPending = 0;
}

final announcementsProvider = FutureProvider.family<List<Announcement>, String>(
  (ref, scope) =>
      ref.read(studentRepositoryProvider).announcements(scope: scope),
);

final contentProvider = FutureProvider.family<ContentItem, String>(
  (ref, id) => ref.read(studentRepositoryProvider).content(id),
);

final contentsProvider = FutureProvider<List<ContentItem>>(
  (ref) => ref.read(studentRepositoryProvider).contents(),
);

final contentEmbedProvider = FutureProvider.family<ContentEmbed, String>(
  (ref, id) => ref.read(studentRepositoryProvider).contentEmbed(id),
);

final contentResumeProvider = FutureProvider.family<ResumeState, String>(
  (ref, id) => ref.read(studentRepositoryProvider).contentResume(id),
);

// ───────────────── Cloudflare Stream videos (new pipeline) ─────────────────

/// Lists every video assigned to a class, grouped by lesson (group_title).
final classVideosProvider = FutureProvider.family<ClassVideos, String>(
  (ref, classId) => ref.read(studentRepositoryProvider).classVideos(classId),
);

/// Mints a short-lived signed playback ticket. We don't auto-cache this
/// because the URL expires; the player asks for it on first mount and
/// re-asks on resume from background when [PlaybackTicket.isFresh] is false.
final videoPlaybackProvider =
    FutureProvider.family.autoDispose<PlaybackTicket, String>(
  (ref, videoId) => ref.read(studentRepositoryProvider).videoPlayback(videoId),
);
