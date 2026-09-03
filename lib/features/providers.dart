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
  final results = await Future.wait([
    repo.dashboard().then<Object?>((v) => v).catchError((_) => null),
    repo.subjects().then<Object?>((v) => v).catchError((_) => <Subject>[]),
    repo
        .enrollments()
        .then<Object?>((v) => v)
        .catchError((_) => <Enrollment>[]),
    repo.quizzes().then<Object?>((v) => v).catchError((_) => <Assignment>[]),
    repo
        .assignments(type: 'homework')
        .then<Object?>((v) => v)
        .catchError((_) => <Assignment>[]),
    repo.contents().then<Object?>((v) => v).catchError((_) => <ContentItem>[]),
  ]);

  final dash = results[0] as StudentDashboard?;
  final subs = (results[1] as List<Subject>? ?? const <Subject>[]);
  final enrollments = (results[2] as List<Enrollment>? ?? const <Enrollment>[]);
  final quizzes = (results[3] as List<Assignment>? ?? const <Assignment>[]);
  final homework = (results[4] as List<Assignment>? ?? const <Assignment>[]);
  final contents = (results[5] as List<ContentItem>? ?? const <ContentItem>[]);

  // Build the enrolled-subjects list:
  // 1) Prefer the dashboard's `classes` (already enrolled).
  // 2) Otherwise, intersect the full subjects feed with active enrollments.
  // 3) As a last resort, fall back to whatever subjects we got.
  List<Subject> subjects;
  if (dash?.subjects.isNotEmpty == true) {
    subjects = dash!.subjects;
  } else if (enrollments.isNotEmpty) {
    final enrolledIds = enrollments
        .where((e) => e.status == 'active' || e.status.isEmpty)
        .map((e) => e.subjectId)
        .toSet();
    final filtered =
        subs.where((s) => enrolledIds.contains(s.id)).toList(growable: false);
    subjects = filtered.isNotEmpty ? filtered : subs;
  } else {
    subjects = subs;
  }
  // Mirror the count to the resolved subjects list so the dashboard's
  // "Subjects" tile matches "Your subjects" below it. Some servers return
  // enrollments without an explicit "active" status, which previously caused
  // the tile to read 0 even though the student had subjects.
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

/// Subjects suggested for the signed-in student to enrol in. Calls the
/// `/student/subjects?filter=available&grade=<n>` endpoint so the user only
/// sees subjects matching their profile grade that they're not already
/// enrolled in / requested. Returns an empty list silently on any error so
/// the suggestion section can simply hide.
final suggestedSubjectsProvider = FutureProvider<List<Subject>>((ref) async {
  final user = ref.watch(authControllerProvider).user;
  final gradeStr = user?.grade;
  final grade = gradeStr == null ? null : int.tryParse(gradeStr.trim());
  if (grade == null) return const <Subject>[];
  try {
    return await ref
        .read(studentRepositoryProvider)
        .subjects(filter: 'available', grade: grade);
  } catch (_) {
    return const <Subject>[];
  }
});

final enrolledSubjectsProvider = FutureProvider<List<Subject>>((ref) async {
  final dashboard = await ref.read(dashboardProvider.future).catchError(
      (_) => const StudentDashboard(subjects: [], overallCompletion: 0));
  final subjects =
      await ref.read(subjectsProvider.future).catchError((_) => <Subject>[]);
  return dashboard.subjects.isNotEmpty ? dashboard.subjects : subjects;
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

final lessonsProvider = FutureProvider.family<List<Lesson>, String>(
  (ref, subjectId) => ref.read(studentRepositoryProvider).lessons(subjectId),
);

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
final classVideosProvider =
    FutureProvider.family<ClassVideos, String>(
  (ref, classId) => ref.read(studentRepositoryProvider).classVideos(classId),
);

/// Mints a short-lived signed playback ticket. We don't auto-cache this
/// because the URL expires; the player asks for it on first mount and
/// re-asks on resume from background when [PlaybackTicket.isFresh] is false.
final videoPlaybackProvider =
    FutureProvider.family.autoDispose<PlaybackTicket, String>(
  (ref, videoId) =>
      ref.read(studentRepositoryProvider).videoPlayback(videoId),
);
