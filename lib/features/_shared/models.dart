import 'package:equatable/equatable.dart';

class Subject extends Equatable {
  const Subject({
    required this.id,
    required this.name,
    this.classId,
    this.description,
    this.coverUrl,
    this.grade,
    this.lessonsCount,
    this.completionPercent,
    this.enrollmentStatus,
  });

  final String id;
  final String name;
  final String? classId;
  final String? description;
  final String? coverUrl;
  final String? grade;
  final int? lessonsCount;
  final double? completionPercent; // 0..1
  final String? enrollmentStatus; // active|pending|none

  factory Subject.fromJson(Map<String, dynamic> j) {
    // The backend sometimes returns the lesson count under different keys
    // (or not at all), but always sends the actual lessons array under
    // `lessons` / `contents`. Derive a count from whichever field exists so
    // the subject card never reads "0 lessons" when there really are some.
    int? derivedCount = _toInt(j['lessons_count'] ?? j['lesson_count']);
    final rawLessons = j['lessons'];
    if ((derivedCount == null || derivedCount == 0) && rawLessons is List) {
      derivedCount = rawLessons.length;
    } else if (derivedCount == null && rawLessons is num) {
      derivedCount = rawLessons.toInt();
    }
    if ((derivedCount == null || derivedCount == 0) &&
        j['contents'] is List) {
      derivedCount = (j['contents'] as List).length;
    }
    return Subject(
      id: (j['_id'] ?? j['id'] ?? j['subject_id'] ?? '').toString(),
      name: (j['title'] ?? j['name'] ?? '').toString(),
      classId: (j['class_id'] ?? j['class'] ?? j['classId'])?.toString(),
      description: j['description']?.toString(),
      coverUrl: (j['cover_url'] ?? j['image'] ?? j['thumbnail'])?.toString(),
      grade: j['grade']?.toString(),
      lessonsCount: derivedCount,
      completionPercent: _toPercent(j['completion_percent'] ?? j['progress']),
      enrollmentStatus: j['enrollment_status']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
      classId,
        description,
        coverUrl,
        grade,
        lessonsCount,
        completionPercent,
        enrollmentStatus
      ];
}

class Lesson extends Equatable {
  const Lesson({
    required this.id,
    required this.title,
    this.subjectId,
    this.order,
    this.duration,
    this.contents = const [],
    this.unlocked = true,
  });

  final String id;
  final String title;
  final String? subjectId;
  final int? order;
  final Duration? duration;
  final List<ContentItem> contents;
  final bool unlocked;

  factory Lesson.fromJson(Map<String, dynamic> j) => Lesson(
        id: (j['_id'] ?? j['id'] ?? j['lesson_id'] ?? '').toString(),
        title: (j['title'] ?? j['name'] ?? '').toString(),
        subjectId: j['subject_id']?.toString(),
        order: _toInt(j['order'] ?? j['position']),
        duration: _toDuration(j['duration'] ?? j['duration_seconds']),
        unlocked: j['unlocked'] != false,
        contents: (j['contents'] as List?)
                ?.whereType<Map>()
                .map((m) => ContentItem.fromJson(Map<String, dynamic>.from(m)))
                .toList() ??
            const [],
      );

  @override
  List<Object?> get props =>
      [id, title, subjectId, order, duration, contents, unlocked];
}

class ContentItem extends Equatable {
  const ContentItem({
    required this.id,
    required this.title,
    required this.type,
    this.lessonId,
    this.subjectId,
    this.className,
    this.description,
    this.duration,
    this.thumbnailUrl,
    this.watched = false,
    this.createdAt,
  });

  final String id;
  final String title;
  final String type; // video, pdf, article
  final String? lessonId;
  final String? subjectId;
  final String? className;
  final String? description;
  final Duration? duration;
  final String? thumbnailUrl;
  final bool watched;
  final DateTime? createdAt;

  factory ContentItem.fromJson(Map<String, dynamic> j) => ContentItem(
        id: (j['_id'] ?? j['id'] ?? j['content_id'] ?? '').toString(),
        title: (j['title'] ?? j['name'] ?? '').toString(),
        type: (j['type'] ?? 'video').toString(),
        lessonId: j['lesson_id']?.toString(),
        subjectId: (j['subject_id'] ?? j['class_id'])?.toString(),
        className: (j['class_name'] ?? j['subject_title'])?.toString(),
        description: j['description']?.toString(),
        duration: _toDuration(j['duration'] ?? j['duration_seconds']),
        thumbnailUrl: j['thumbnail_url']?.toString(),
        watched: j['watched'] == true,
        createdAt: _toDate(j['created_at']),
      );

  @override
  List<Object?> get props => [
        id,
        title,
        type,
        lessonId,
        subjectId,
        className,
        description,
        duration,
        thumbnailUrl,
        watched,
        createdAt,
      ];
}

class ContentEmbed extends Equatable {
  const ContentEmbed({required this.embedUrl, this.duration, this.provider});
  final String embedUrl;
  final Duration? duration;
  final String? provider;

  factory ContentEmbed.fromJson(Map<String, dynamic> j) => ContentEmbed(
        embedUrl: (j['embed_url'] ?? j['url'] ?? '').toString(),
        duration: _toDuration(j['duration'] ?? j['duration_seconds']),
        provider: j['provider']?.toString(),
      );

  @override
  List<Object?> get props => [embedUrl, duration, provider];
}

class ResumeState extends Equatable {
  const ResumeState(
      {required this.resumeFromSeconds, required this.completionPercent});
  final int resumeFromSeconds;
  final double completionPercent; // 0..1

  factory ResumeState.fromJson(Map<String, dynamic> j) => ResumeState(
        resumeFromSeconds:
            _toInt(j['resume_from'] ?? j['resume_from_seconds']) ?? 0,
        completionPercent:
            _toPercent(j['completion_percent'] ?? j['completion']) ?? 0,
      );

  @override
  List<Object?> get props => [resumeFromSeconds, completionPercent];
}

class SubjectProgress extends Equatable {
  const SubjectProgress({
    required this.subjectId,
    required this.totalWatchedSeconds,
    required this.completionPercent,
    this.lessonsCompleted,
    this.lessonsTotal,
  });

  final String subjectId;
  final int totalWatchedSeconds;
  final double completionPercent; // 0..1
  final int? lessonsCompleted;
  final int? lessonsTotal;

  factory SubjectProgress.fromJson(Map<String, dynamic> j) => SubjectProgress(
        subjectId: (j['subject_id'] ?? '').toString(),
        totalWatchedSeconds: _toInt(j['total_watched_seconds']) ?? 0,
        completionPercent:
            _toPercent(j['completion_percent'] ?? j['completion']) ?? 0,
        lessonsCompleted: _toInt(j['lessons_completed']),
        lessonsTotal: _toInt(j['lessons_total']),
      );

  @override
  List<Object?> get props => [
        subjectId,
        totalWatchedSeconds,
        completionPercent,
        lessonsCompleted,
        lessonsTotal
      ];
}

class Enrollment extends Equatable {
  const Enrollment({
    required this.id,
    required this.subjectId,
    required this.status,
    this.subjectName,
    this.requestedAt,
  });

  final String id;
  final String subjectId;
  final String status; // pending|active|rejected
  final String? subjectName;
  final DateTime? requestedAt;

  factory Enrollment.fromJson(Map<String, dynamic> j) => Enrollment(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        subjectId: (j['subject_id'] ?? '').toString(),
        subjectName:
            (j['subject_title'] ?? j['subject_name'] ?? j['subject']?['name'])
                ?.toString(),
        status: (j['status'] ?? 'pending').toString(),
        requestedAt:
            _toDate(j['enrolled_at'] ?? j['requested_at'] ?? j['created_at']),
      );

  @override
  List<Object?> get props => [id, subjectId, subjectName, status, requestedAt];
}

class Announcement extends Equatable {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.publishedAt,
    this.scope,
    this.scopeId,
  });

  final String id;
  final String title;
  final String body;
  final DateTime publishedAt;
  final String? scope; // global|subject|class
  final String? scopeId;

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? j['message'] ?? j['content'] ?? '').toString(),
        publishedAt:
            _toDate(j['published_at'] ?? j['created_at']) ?? DateTime.now(),
        scope: j['scope']?.toString(),
        scopeId: (j['scope_id'] ?? j['target_id'])?.toString(),
      );

  @override
  List<Object?> get props => [id, title, body, publishedAt, scope, scopeId];
}

class Assignment extends Equatable {
  const Assignment({
    required this.id,
    required this.title,
    required this.type, // homework|quiz
    this.subjectId,
    this.subjectName,
    this.description,
    this.dueAt,
    this.status, // pending|submitted|graded|late
    this.score,
    this.maxScore,
    this.attachmentUrl,
    this.feedback,
    this.allowResubmit = true,
  });

  final String id;
  final String title;
  final String type;
  final String? subjectId;
  final String? subjectName;
  final String? description;
  final DateTime? dueAt;
  final String? status;
  final num? score;
  final num? maxScore;
  final String? attachmentUrl;
  final String? feedback;
  final bool allowResubmit;

  factory Assignment.fromJson(Map<String, dynamic> j) {
    // The list endpoint returns a flat `submission_status`. The detail
    // endpoint returns the assignment's own publish status at the top level
    // ("active" / "draft") and nests the student's submission inside a
    // `submission: {...}` object. Resolve the *submission* status from
    // whichever shape the server used.
    final submission = j['submission'] is Map
        ? Map<String, dynamic>.from(j['submission'] as Map)
        : null;
    final rawSubmissionStatus = j['submission_status']?.toString();
    final nestedSubmissionStatus = submission?['status']?.toString();
    String? submissionStatus = rawSubmissionStatus ?? nestedSubmissionStatus;
    if (submissionStatus == null && submission != null) {
      // Submission object exists but has no explicit status → treat as
      // submitted.
      submissionStatus =
          (submission['score'] != null) ? 'graded' : 'submitted';
    }
    // Sanitize: ignore non-submission status strings (e.g. "active") that
    // would otherwise leak through and look like "Pending" downstream.
    const validStatuses = {'pending', 'submitted', 'graded', 'late'};
    if (submissionStatus != null &&
        !validStatuses.contains(submissionStatus)) {
      submissionStatus = null;
    }

    return Assignment(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        title: (j['title'] ?? j['name'] ?? '').toString(),
        type: (j['type'] ?? 'homework').toString(),
        subjectId: (j['subject_id'] ?? j['class_id'])?.toString(),
        subjectName:
            (j['subject_name'] ?? j['class_name'] ?? j['subject']?['name'])
                ?.toString(),
        description: j['description']?.toString(),
        dueAt: _toDate(j['due_at'] ?? j['due_date']),
        status: submissionStatus,
        score: _toNum(j['score'] ?? submission?['score']),
        maxScore: _toNum(j['max_score'] ?? j['total_score']),
        attachmentUrl: (j['attachment_url'] ??
                (j['attachment'] is Map ? j['attachment']['url'] : null))
            ?.toString(),
        feedback: (j['feedback'] ?? submission?['feedback'])?.toString(),
        allowResubmit:
            j['allow_resubmit'] != false && submissionStatus != 'graded',
      );
  }

  bool get isOverdue {
    final due = dueAt;
    if (due == null) return false;
    return DateTime.now().isAfter(due) &&
        status != 'submitted' &&
        status != 'graded';
  }

  @override
  List<Object?> get props => [
        id,
        title,
        type,
        subjectId,
        subjectName,
        description,
        dueAt,
        status,
        score,
        maxScore,
        attachmentUrl,
        feedback,
        allowResubmit,
      ];
}

class NotificationItem extends Equatable {
  const NotificationItem({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.read,
    this.category, // announcement|assignment_due|quiz_due|grade_posted|enrollment_update|system
    this.deepLink,
    this.data,
  });

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final String? category;
  final String? deepLink;
  final Map<String, dynamic>? data;

  factory NotificationItem.fromJson(Map<String, dynamic> j) => NotificationItem(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        body: (j['body'] ?? j['message'] ?? '').toString(),
        createdAt: _toDate(j['created_at'] ?? j['sent_at']) ?? DateTime.now(),
        read: j['is_read'] == true || j['read'] == true || j['read_at'] != null,
        category: (j['category'] ?? j['type'])?.toString(),
        deepLink: (j['deep_link'] ?? j['url'])?.toString(),
        data: j['data'] is Map
            ? Map<String, dynamic>.from(j['data'] as Map)
            : null,
      );

  NotificationItem copyWith({bool? read}) => NotificationItem(
        id: id,
        title: title,
        body: body,
        createdAt: createdAt,
        read: read ?? this.read,
        category: category,
        deepLink: deepLink,
        data: data,
      );

  @override
  List<Object?> get props =>
      [id, title, body, createdAt, read, category, deepLink];
}

class StudentDashboard extends Equatable {
  const StudentDashboard({
    required this.subjects,
    required this.overallCompletion,
    this.totalWatchedSeconds = 0,
    this.pendingAssignments = 0,
    this.pendingQuizzes = 0,
    this.unreadNotifications = 0,
    this.enrolledCount = 0,
    this.quizCount = 0,
    this.assignmentCount = 0,
    this.contentCount = 0,
  });

  final List<Subject> subjects;
  final double overallCompletion;
  final int totalWatchedSeconds;
  final int pendingAssignments;
  final int pendingQuizzes;
  final int unreadNotifications;
  final int enrolledCount;
  final int quizCount;
  final int assignmentCount;
  final int contentCount;

  factory StudentDashboard.fromJson(Map<String, dynamic> j) {
    // The API returns `classes` (the student's enrolled classes). Map them
    // into our Subject model so the dashboard tile list works.
    List<Map<String, dynamic>> raw = (j['subjects'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList() ??
        const <Map<String, dynamic>>[];
    final fromClasses = raw.isEmpty;
    if (fromClasses) {
      raw = (j['classes'] as List?)
              ?.whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList() ??
          const <Map<String, dynamic>>[];
    }
    // For class entities, prefer `subject_id` so downstream endpoints
    // like /student/subjects/<id>/lessons hit the real subject id rather
    // than the class id.
    final subs = raw.map((m) {
      if (fromClasses) {
        final remapped = Map<String, dynamic>.from(m);
        final subjectId = m['subject_id'] ?? m['subject']?.toString();
        if (subjectId != null) {
          remapped['_id'] = subjectId;
          remapped['id'] = subjectId;
        }
        // Preserve class id for /api/student/classes/<id>/videos while
        // keeping Subject.id as subject_id for lessons/content endpoints.
        remapped['class_id'] = (m['_id'] ?? m['id'] ?? '').toString();
        // Carry subject_title forward as the display name when available.
        if (m['subject_title'] != null) {
          remapped['title'] = m['subject_title'];
        }
        return Subject.fromJson(remapped);
      }
      return Subject.fromJson(m);
    }).toList();

    final kpis = (j['kpis'] is Map)
        ? Map<String, dynamic>.from(j['kpis'] as Map)
        : const <String, dynamic>{};

    final hwList = (j['homework_assignments'] as List?) ?? const [];
    final qzList = (j['quiz_assignments'] as List?) ?? const [];
    final pending = _toInt(kpis['not_submitted']) ??
        _toInt(j['pending_assignments']) ??
        (hwList.length + qzList.length);

    final overall = _toPercent(j['overall_completion'] ?? j['completion']) ??
        (subs.isEmpty
            ? 0
            : subs
                    .map((s) => s.completionPercent ?? 0)
                    .fold<double>(0, (a, b) => a + b) /
                subs.length);

    return StudentDashboard(
      subjects: subs,
      overallCompletion: overall,
      totalWatchedSeconds: _toInt(j['total_watched_seconds']) ?? 0,
      pendingAssignments: pending,
      unreadNotifications: _toInt(j['unread_notifications']) ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        subjects,
        overallCompletion,
        totalWatchedSeconds,
        pendingAssignments,
        pendingQuizzes,
        unreadNotifications,
        enrolledCount,
        quizCount,
        assignmentCount,
        contentCount,
      ];
}

// ───────────────────────── Cloudflare Stream videos ─────────────────────────

/// A single Cloudflare Stream video (one clip / "part" inside a lesson group).
/// Returned by `GET /api/student/classes/<class_id>/videos`.
class VideoItem extends Equatable {
  const VideoItem({
    required this.id,
    required this.title,
    required this.streamUid,
    this.orderIndex = 0,
    this.durationSeconds = 0,
    this.thumbnailUrl,
    this.isVisible = true,
    this.watchedSeconds = 0,
    this.completed = false,
  });

  /// Backend Mongo id (used for /playback and /progress calls).
  final String id;
  final String title;

  /// 32-char Cloudflare Stream UID. Never expose this to a player directly —
  /// always go through the signed [PlaybackTicket].
  final String streamUid;
  final int orderIndex;
  final int durationSeconds;
  final String? thumbnailUrl;
  final bool isVisible;
  final int watchedSeconds;
  final bool completed;

  Duration get duration => Duration(seconds: durationSeconds);

  double get progress {
    if (durationSeconds <= 0) return 0;
    return (watchedSeconds / durationSeconds).clamp(0, 1).toDouble();
  }

  factory VideoItem.fromJson(Map<String, dynamic> j) => VideoItem(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        title: (j['title'] ?? '').toString(),
        streamUid: (j['stream_uid'] ?? j['uid'] ?? '').toString(),
        orderIndex: _toInt(j['order_index']) ?? 0,
        durationSeconds: _toInt(j['duration']) ?? 0,
        thumbnailUrl: j['thumbnail']?.toString(),
        isVisible: j['is_visible'] != false,
        watchedSeconds: _toInt(j['watched_seconds']) ?? 0,
        completed: j['completed'] == true,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        streamUid,
        orderIndex,
        durationSeconds,
        thumbnailUrl,
        isVisible,
        watchedSeconds,
        completed,
      ];
}

/// A group of [VideoItem]s belonging to the same lesson (same `group_title`).
class VideoGroup extends Equatable {
  const VideoGroup({
    required this.title,
    required this.videos,
    this.totalDurationSeconds = 0,
  });

  final String title;
  final List<VideoItem> videos;
  final int totalDurationSeconds;

  int get videoCount => videos.length;

  Duration get totalDuration => Duration(seconds: totalDurationSeconds);

  /// Display-only: returns [v.title] with the leading "<group title> — "
  /// (or " - ") prefix stripped, so the carousel shows just "part_1.mp4"
  /// rather than the lesson title repeated on every card.
  String displayTitleFor(VideoItem v) {
    final t = v.title;
    final prefixes = ['$title — ', '$title - ', '$title – '];
    for (final p in prefixes) {
      if (t.startsWith(p)) return t.substring(p.length);
    }
    return t;
  }

  /// True once every visible video in the group is past the 90% completion
  /// threshold (matches backend `completed` flag).
  bool get isComplete =>
      videos.isNotEmpty && videos.every((v) => v.completed);

  factory VideoGroup.fromJson(Map<String, dynamic> j) {
    final raw = (j['videos'] as List?) ??
        (j['items'] as List?) ??
        (j['clips'] as List?) ??
        const [];
    final videos = raw
        .whereType<Map>()
        .map((m) => VideoItem.fromJson(Map<String, dynamic>.from(m)))
        .where((v) => v.isVisible && v.streamUid.isNotEmpty)
        .toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return VideoGroup(
      title: (j['title'] ?? j['group_title'] ?? j['name'] ?? '').toString(),
      videos: videos,
      totalDurationSeconds: _toInt(j['total_duration']) ??
          videos.fold<int>(0, (sum, v) => sum + v.durationSeconds),
    );
  }

  @override
  List<Object?> get props => [title, totalDurationSeconds, videos];
}

/// Top-level payload from `/api/student/classes/<id>/videos`.
class ClassVideos extends Equatable {
  const ClassVideos({
    required this.classId,
    required this.classTitle,
    required this.groups,
  });

  final String classId;
  final String classTitle;
  final List<VideoGroup> groups;

  factory ClassVideos.fromJson(Map<String, dynamic> j) {
    final cls = j['class'] is Map
        ? Map<String, dynamic>.from(j['class'] as Map)
        : const <String, dynamic>{};
    final rawGroups = (j['groups'] as List?) ??
        (j['video_groups'] as List?) ??
        (j['lessons'] as List?) ??
        const [];
    var groups = rawGroups
        .whereType<Map>()
        .map((m) => VideoGroup.fromJson(Map<String, dynamic>.from(m)))
        .where((g) => g.videos.isNotEmpty)
        .toList();

    // Fallback shape: flat `videos` list carrying `group_title` per row.
    if (groups.isEmpty && j['videos'] is List) {
      final rows = (j['videos'] as List)
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final byGroup = <String, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        final title = (row['group_title'] ?? row['group'] ?? 'Ungrouped')
            .toString()
            .trim();
        byGroup.putIfAbsent(title, () => <Map<String, dynamic>>[]).add(row);
      }
      groups = byGroup.entries
          .map(
            (e) => VideoGroup.fromJson({
              'title': e.key,
              'videos': e.value,
            }),
          )
          .where((g) => g.videos.isNotEmpty)
          .toList();
    }

    return ClassVideos(
      classId: (cls['id'] ?? cls['_id'] ?? j['class_id'] ?? j['id'] ?? '')
          .toString(),
      classTitle:
          (cls['title'] ?? cls['name'] ?? j['class_title'] ?? '').toString(),
      groups: groups,
    );
  }

  @override
  List<Object?> get props => [classId, classTitle, groups];
}

/// Short-lived, user-bound signed playback descriptor returned by
/// `POST /api/student/videos/<video_id>/playback`.
class PlaybackTicket extends Equatable {
  const PlaybackTicket({
    required this.streamUid,
    required this.hlsUrl,
    required this.dashUrl,
    required this.iframeUrl,
    required this.expiresAt,
    this.posterUrl,
    this.fairplay = false,
    this.widevine = false,
  });

  final String streamUid;
  final String hlsUrl;
  final String dashUrl;
  final String iframeUrl;
  final String? posterUrl;
  final DateTime expiresAt;

  /// Per-platform DRM availability flags from the backend. The spec requires
  /// playback to be refused if the flag for the current platform is false.
  final bool fairplay;
  final bool widevine;

  /// Returns true if the ticket is still valid for at least [bufferSeconds]
  /// (default 30s). Used to decide whether to mint a fresh URL on resume.
  bool isFresh({int bufferSeconds = 30}) {
    return DateTime.now()
        .add(Duration(seconds: bufferSeconds))
        .isBefore(expiresAt);
  }

  factory PlaybackTicket.fromJson(Map<String, dynamic> j) {
    final drm = j['drm'] is Map
        ? Map<String, dynamic>.from(j['drm'] as Map)
        : const <String, dynamic>{};
    return PlaybackTicket(
      streamUid: (j['stream_uid'] ?? j['uid'] ?? '').toString(),
      hlsUrl: (j['hls_url'] ?? '').toString(),
      dashUrl: (j['dash_url'] ?? '').toString(),
      iframeUrl: (j['iframe_url'] ?? '').toString(),
      posterUrl: (j['poster'] ?? j['thumbnail'])?.toString(),
      expiresAt: _toDate(j['expires_at']) ??
          DateTime.now().add(const Duration(minutes: 1)),
      fairplay: drm['fairplay'] == true,
      widevine: drm['widevine'] == true,
    );
  }

  @override
  List<Object?> get props => [
        streamUid,
        hlsUrl,
        dashUrl,
        iframeUrl,
        posterUrl,
        expiresAt,
        fairplay,
        widevine,
      ];
}

// ---------- helpers ----------

int? _toInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

num? _toNum(Object? v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}

double? _toPercent(Object? v) {
  if (v == null) return null;
  if (v is num) {
    final d = v.toDouble();
    return d > 1.0
        ? (d / 100.0).clamp(0, 1).toDouble()
        : d.clamp(0, 1).toDouble();
  }
  if (v is String) {
    final d = double.tryParse(v.replaceAll('%', ''));
    if (d == null) return null;
    return d > 1.0
        ? (d / 100.0).clamp(0, 1).toDouble()
        : d.clamp(0, 1).toDouble();
  }
  return null;
}

Duration? _toDuration(Object? v) {
  final s = _toInt(v);
  if (s == null) return null;
  return Duration(seconds: s);
}

DateTime? _toDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  return null;
}
