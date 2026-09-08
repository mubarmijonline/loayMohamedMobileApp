import 'dart:typed_data';

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

  /// Actively enrolled — the student may open lessons and content.
  ///
  /// `pending` is NOT enrolled: the request exists but has not been approved,
  /// and every content route will still answer `403 not_enrolled`.
  bool get isEnrolled => enrollmentStatus == 'active';

  bool get isPendingEnrollment => enrollmentStatus == 'pending';

  /// The server said, one way or the other. Dashboard `classes` carry no
  /// status field (they are enrolled by definition), so null means "unknown",
  /// never "not enrolled".
  bool get hasEnrollmentStatus => enrollmentStatus != null;

  factory Subject.fromJson(Map<String, dynamic> j) {
    // The backend sometimes returns the lesson count under different keys
    // (or not at all), but always sends the actual lessons array under
    // `lessons` / `contents`. Derive a count from whichever field exists so
    // the subject card never reads "0 lessons" when there really are some.
    int? derivedCount = _toInt(j['lessons_count'] ?? j['lesson_count']);
    final rawLessons = j['lessons'];
    if ((derivedCount == null || derivedCount == 0) && rawLessons is List) {
      derivedCount = rawLessons.length;
    } else if (derivedCount == null && rawLessons != null) {
      // `lessons` may arrive as a bare count, and as a numeric *string* —
      // _toInt handles both. Matching only `num` here silently dropped "12".
      derivedCount = _toInt(rawLessons);
    }
    if ((derivedCount == null || derivedCount == 0) && j['contents'] is List) {
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
        enrollmentStatus,
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
    this.classId,
    this.subjectId,
    this.className,
    this.groupTitle,
    this.orderIndex,
    this.description,
    this.duration,
    this.thumbnailUrl,
    this.provider,
    this.watched = false,
    this.createdAt,
  });

  final String id;
  final String title;
  final String type; // video, handout, link
  final String? lessonId;

  /// The `teacher_classes` id this item belongs to. Sections break on it.
  final String? classId;

  final String? subjectId;
  final String? className;

  /// The folder name the teacher set.
  ///
  /// **Never null from the API**: items with no group arrive as the literal
  /// `"(Ungrouped)"`, so it renders as its own section with no special case
  /// (API_BRIEF §6).
  final String? groupTitle;

  /// The `#1` / `#2` badge. Per group, not global.
  final int? orderIndex;

  final String? description;
  final Duration? duration;

  /// `/api/v1/student/content/<id>/thumbnail`, or null when the item has no
  /// poster. **Token-protected** — it needs the auth header, so a plain
  /// `Image.network` gets a 401.
  final String? thumbnailUrl;

  final String? provider; // bunny | cloudflare | drive | null
  final bool watched;
  final DateTime? createdAt;

  /// `mm:ss`, matching the portal's card badge.
  String get durationLabel {
    final d = duration;
    if (d == null || d == Duration.zero) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  factory ContentItem.fromJson(Map<String, dynamic> j) => ContentItem(
        id: (j['_id'] ?? j['id'] ?? j['content_id'] ?? '').toString(),
        title: (j['title'] ?? j['name'] ?? '').toString(),
        type: (j['type'] ?? 'video').toString(),
        lessonId: j['lesson_id']?.toString(),
        classId: j['class_id']?.toString(),
        subjectId: (j['subject_id'] ?? j['class_id'])?.toString(),
        className: (j['class_name'] ?? j['subject_title'])?.toString(),
        groupTitle: j['group_title']?.toString(),
        orderIndex: _toInt(j['order_index']),
        description: j['description']?.toString(),
        duration: _toDuration(j['duration'] ?? j['duration_seconds']),
        thumbnailUrl: j['thumbnail_url']?.toString(),
        provider: j['provider']?.toString(),
        watched: j['watched'] == true,
        createdAt: _toDate(j['created_at']),
      );

  @override
  List<Object?> get props => [
        id,
        title,
        type,
        lessonId,
        classId,
        subjectId,
        className,
        groupTitle,
        orderIndex,
        description,
        duration,
        thumbnailUrl,
        provider,
        watched,
        createdAt,
      ];
}

/// One class, from `GET /student/classes` (API_BRIEF §6).
///
/// Fills the section header on the Videos screen: the title, and the
/// "6/10 watched" pill.
class StudentClass extends Equatable {
  const StudentClass({
    required this.id,
    required this.name,
    this.level,
    this.subject,
    this.teacherName,
    this.coverUrl,
    this.examBoard,
    this.isActive = true,
    this.videoTotal = 0,
    this.videoWatched = 0,
    this.homeworkTotal = 0,
    this.homeworkDone = 0,
    this.quizTotal = 0,
    this.quizDone = 0,
    this.completionPercent = 0,
  });

  final String id;
  final String name;
  final String? level;
  final String? subject;
  final String? teacherName;
  final String? coverUrl;
  final String? examBoard;
  final bool isActive;

  final int videoTotal;
  final int videoWatched;
  final int homeworkTotal;
  final int homeworkDone;
  final int quizTotal;
  final int quizDone;
  final num completionPercent;

  /// "6/10 watched".
  String get watchedLabel => '$videoWatched/$videoTotal watched';

  factory StudentClass.fromJson(Map<String, dynamic> j) => StudentClass(
        id: (j['_id'] ?? j['id'] ?? '').toString(),
        name: (j['name'] ?? j['title'] ?? '').toString(),
        level: j['level']?.toString(),
        subject: j['subject']?.toString(),
        teacherName: j['teacher_name']?.toString(),
        coverUrl: j['cover_url']?.toString(),
        examBoard: j['exam_board']?.toString(),
        isActive: j['is_active'] != false,
        videoTotal: _toInt(j['video_total']) ?? 0,
        videoWatched: _toInt(j['video_watched']) ?? 0,
        homeworkTotal: _toInt(j['homework_total']) ?? 0,
        homeworkDone: _toInt(j['homework_done']) ?? 0,
        quizTotal: _toInt(j['quiz_total']) ?? 0,
        quizDone: _toInt(j['quiz_done']) ?? 0,
        completionPercent: _toNum(j['completion_percent']) ?? 0,
      );

  @override
  List<Object?> get props => [id, name, videoTotal, videoWatched];
}

/// A run of content sharing one `group_title`, within one class.
class ContentGroup extends Equatable {
  const ContentGroup({required this.title, required this.items});

  final String title;
  final List<ContentItem> items;

  @override
  List<Object?> get props => [title, items];
}

/// One class and its groups, ready to render.
class ContentSection extends Equatable {
  const ContentSection({
    required this.classId,
    required this.className,
    required this.groups,
    this.studentClass,
  });

  final String classId;
  final String className;
  final List<ContentGroup> groups;

  /// The matching `/student/classes` row, when one was found. Carries the
  /// watched pill.
  final StudentClass? studentClass;

  int get videoCount => groups.fold(0, (a, g) => a + g.items.length);

  /// "4 groups • 10 videos" — computed client-side, as the portal does.
  String get summary {
    final g = groups.length;
    final v = videoCount;
    return '$g ${g == 1 ? 'group' : 'groups'} • $v ${v == 1 ? 'video' : 'videos'}';
  }

  /// Groups a flat `/student/content` response the way the portal does.
  ///
  /// **The list arrives already sorted by
  /// `(class_id, group_title, order_index, created_at)`.** Walk it once in the
  /// order given and open a new section whenever `class_id` or `group_title`
  /// changes.
  ///
  /// Do not re-sort, and specifically do not sort by `created_at` — that was
  /// the old mobile behaviour, and it is what produced a flat undivided list
  /// with no course title above it.
  static List<ContentSection> group(
    List<ContentItem> items, {
    List<StudentClass> classes = const [],
  }) {
    final byId = {for (final c in classes) c.id: c};
    final sections = <ContentSection>[];

    String? currentClass;
    String? currentGroup;
    var groups = <ContentGroup>[];
    var bucket = <ContentItem>[];

    void closeGroup() {
      if (bucket.isNotEmpty) {
        groups.add(
            ContentGroup(title: currentGroup ?? '(Ungrouped)', items: bucket));
        bucket = <ContentItem>[];
      }
    }

    void closeSection() {
      closeGroup();
      if (groups.isNotEmpty) {
        final id = currentClass ?? '';
        sections.add(ContentSection(
          classId: id,
          className:
              byId[id]?.name ?? groups.first.items.first.className ?? 'Course',
          groups: groups,
          studentClass: byId[id],
        ));
        groups = <ContentGroup>[];
      }
    }

    for (final item in items) {
      final cls = item.classId ?? item.subjectId ?? '';
      final grp = item.groupTitle ?? '(Ungrouped)';
      if (cls != currentClass) {
        closeSection();
        currentClass = cls;
        currentGroup = grp;
      } else if (grp != currentGroup) {
        closeGroup();
        currentGroup = grp;
      }
      bucket.add(item);
    }
    closeSection();
    return sections;
  }

  @override
  List<Object?> get props => [classId, className, groups];
}

/// Which service is serving this video (API_BRIEF §6).
///
/// Precedence is resolved server-side: bunny > cloudflare > drive.
enum VideoProvider {
  /// Signed iframe, expires (default 1 hour). Backend also returns the
  /// watermark string.
  bunny,

  /// Unsigned iframe URL.
  cloudflare,

  /// Unsigned, permanent, and **identical for every student**. Everything
  /// protecting Drive content lives in the client and in the Drive file's own
  /// sharing settings.
  drive,

  unknown;

  static VideoProvider parse(Object? v) => switch (v?.toString()) {
        'bunny' => VideoProvider.bunny,
        'cloudflare' => VideoProvider.cloudflare,
        'drive' => VideoProvider.drive,
        _ => VideoProvider.unknown,
      };

  /// Only Bunny URLs carry an expiry; the others never go stale.
  bool get isSigned => this == VideoProvider.bunny;
}

class ContentEmbed extends Equatable {
  const ContentEmbed({
    required this.embedUrl,
    required this.provider,
    this.streamUrl,
    this.duration,
    this.watermark,
    this.streamUid,
    this.bunnyVideoId,
    this.fetchedAt,
    this.apiOrigin,
  });

  /// **Deprecated by the backend.** For Drive this is the unsigned public
  /// `https://drive.google.com/file/d/<id>/preview`, which anyone can watch
  /// without an account. Kept only so builds already in the field keep
  /// working (API_BRIEF §6). Play [streamUrl] instead.
  final String embedUrl;

  /// The URL to actually play.
  ///
  /// For Drive this is `/api/v1/student/content/<id>/drive-stream` on our own
  /// origin: the backend fetches the bytes with the Drive service account and
  /// forwards them as `video/mp4` with `Accept-Ranges: bytes`, honouring the
  /// client's `Range` header. The Drive file id never reaches the device,
  /// there is no Google player, and so there is no share button, pop-out or
  /// download item to hide.
  ///
  /// For Bunny and Cloudflare it is the same iframe URL as [embedUrl].
  final String? streamUrl;
  final VideoProvider provider;
  final Duration? duration;

  /// `Full Name · +20… · <user_id>` — returned **only for Bunny**
  /// (API_BRIEF §6). For Drive and Cloudflare the client must build the same
  /// string from `/auth/me` and draw it as an overlay.
  final String? watermark;

  final String? streamUid;
  final String? bunnyVideoId;

  /// When this embed was minted locally. Used to decide whether a signed URL
  /// has aged past its TTL while the player sat open.
  final DateTime? fetchedAt;

  /// Our own API origin, e.g. `https://loaymotawie.com`.
  ///
  /// Set by [resolvedAgainst] at the repository boundary. Two things depend on
  /// it: turning the backend's relative `stream_url` into something a player
  /// can actually open, and deciding whether the URL is ours (native player,
  /// bearer token) or a third party's (WebView, never a token).
  final String? apiOrigin;

  /// Makes the URLs absolute and records which origin is ours.
  ///
  /// The backend returns `stream_url` as a **path** —
  /// `/api/v1/student/content/<id>/drive-stream`. Dio resolves those against
  /// its `baseUrl`; `video_player` and `WebView` do not. Handing either a
  /// schemeless URI is not an error they report — `Uri.tryParse` returns a
  /// perfectly valid *relative* Uri, so the null check passes, the platform
  /// gets something it cannot open, and the player renders black under a
  /// working watermark. That was the bug.
  ContentEmbed resolvedAgainst(String origin) {
    final base = Uri.tryParse(origin);
    String? abs(String? raw) {
      if (raw == null || raw.trim().isEmpty) return raw;
      final u = Uri.tryParse(raw.trim());
      if (u == null) return raw;
      if (u.hasScheme) return u.toString();
      if (base == null) return raw;
      return base.resolveUri(u).toString();
    }

    return ContentEmbed(
      embedUrl: abs(embedUrl) ?? '',
      streamUrl: abs(streamUrl),
      provider: provider,
      duration: duration,
      watermark: watermark,
      streamUid: streamUid,
      bunnyVideoId: bunnyVideoId,
      fetchedAt: fetchedAt,
      apiOrigin: base?.origin,
    );
  }

  /// Bunny embeds are signed with a default 1 hour TTL
  /// (`BUNNY_STREAM_EMBED_TTL_SECONDS`). Re-fetch `/embed` past that or the
  /// iframe starts refusing to play mid-lesson.
  static const signedTtl = Duration(minutes: 55);

  bool get isStale {
    if (!provider.isSigned) return false;
    final at = fetchedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) >= signedTtl;
  }

  bool get hasVideo => playbackUrl.isNotEmpty;

  /// What to hand the player: [streamUrl] when present, [embedUrl] otherwise.
  ///
  /// API_BRIEF §6: "Play `stream_url`. Ignore `embed_url` unless `stream_url`
  /// is missing."
  String get playbackUrl {
    final s = streamUrl;
    if (s != null && s.trim().isNotEmpty) return s;
    return embedUrl;
  }

  /// True when [playbackUrl] is our own proxy: raw mp4, on our origin, behind
  /// the bearer token.
  ///
  /// Deliberately keyed on the origin rather than on `provider == drive`.
  /// `provider` is a free-text field the backend has not always sent, and
  /// `VideoProvider.parse` turns anything unrecognised into `unknown` — which
  /// silently routed a perfectly good proxy URL into the WebView, where the
  /// iframe branch then played `embed_url` (the *public* Drive preview of a
  /// private file) or nothing at all. Ownership of the URL is the fact that
  /// actually decides which player can open it.
  bool get isProxied {
    final s = streamUrl;
    final o = apiOrigin;
    if (s == null || s.trim().isEmpty || o == null) return false;
    final u = Uri.tryParse(s);
    if (u == null || !u.hasScheme || !u.hasAuthority) return false;
    return u.origin == o;
  }

  /// Our own proxy plays natively; anything third-party stays in the WebView,
  /// where the navigation allowlist and control-strip overlay apply.
  bool get needsWebView => !isProxied;

  /// True when the player must send `Authorization` — our own proxy does, a
  /// third-party iframe must never.
  bool get needsAuthHeader => isProxied;

  factory ContentEmbed.fromJson(Map<String, dynamic> j) => ContentEmbed(
        embedUrl: (j['embed_url'] ?? j['url'] ?? '').toString(),
        streamUrl: j['stream_url']?.toString(),
        provider: VideoProvider.parse(j['provider']),
        duration: _toDuration(j['duration'] ?? j['duration_seconds']),
        watermark: j['watermark']?.toString(),
        streamUid: j['stream_uid']?.toString(),
        bunnyVideoId: j['bunny_video_id']?.toString(),
        fetchedAt: DateTime.now(),
      );

  /// SECURITY: `embed_url` must never reach logs, crash reports or the
  /// clipboard. Keep it out of `toString()`.
  @override
  String toString() =>
      'ContentEmbed(provider: ${provider.name}, hasUrl: ${playbackUrl.isNotEmpty})';

  @override
  List<Object?> get props => [
        embedUrl,
        streamUrl,
        provider,
        duration,
        watermark,
        streamUid,
        bunnyVideoId,
        apiOrigin,
      ];
}

class ResumeState extends Equatable {
  const ResumeState({
    required this.resumeFromSeconds,
    required this.completionPercent,
  });
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
        lessonsTotal,
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

/// One row of the marker's breakdown (API_BRIEF §7, "marking.parts").
///
/// `ok` is derived server-side from `awarded == max`; it is not stored.
class MarkingPart extends Equatable {
  const MarkingPart({
    required this.label,
    this.topic,
    this.max,
    this.awarded,
    this.comment,
    this.ok = false,
  });

  final String label;
  final String? topic;
  final num? max;
  final num? awarded;
  final String? comment;
  final bool ok;

  factory MarkingPart.fromJson(Map<String, dynamic> j) => MarkingPart(
        label: (j['label'] ?? '').toString(),
        topic: j['topic']?.toString(),
        max: _toNum(j['max']),
        awarded: _toNum(j['awarded']),
        comment: j['comment']?.toString(),
        ok: j['ok'] == true,
      );

  @override
  List<Object?> get props => [label, topic, max, awarded, comment, ok];
}

/// Exam metadata attached to a marked script.
class MarkingExam extends Equatable {
  const MarkingExam({this.number, this.session, this.board});

  final String? number;
  final String? session;
  final String? board;

  factory MarkingExam.fromJson(Map<String, dynamic> j) => MarkingExam(
        number: j['number']?.toString(),
        session: j['session']?.toString(),
        board: j['board']?.toString(),
      );

  bool get isEmpty => number == null && session == null && board == null;

  @override
  List<Object?> get props => [number, session, board];
}

/// The released marking breakdown (API_BRIEF §7).
///
/// Totals are recomputed server-side from `parts`, so the breakdown and the
/// total can never disagree — render [totalAwarded] / [totalMax] as given
/// rather than re-summing client-side.
class Marking extends Equatable {
  const Marking({
    this.parts = const [],
    this.totalAwarded,
    this.totalMax,
    this.percentage,
    this.strengths = const [],
    this.priorities = const [],
    this.target,
    this.exam,
  });

  final List<MarkingPart> parts;
  final num? totalAwarded;
  final num? totalMax;
  final num? percentage;
  final List<String> strengths;
  final List<String> priorities;
  final String? target;
  final MarkingExam? exam;

  factory Marking.fromJson(Map<String, dynamic> j) {
    List<String> strings(Object? v) =>
        (v as List?)
            ?.map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList() ??
        const [];
    return Marking(
      parts: (j['parts'] as List?)
              ?.whereType<Map>()
              .map((m) => MarkingPart.fromJson(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
      totalAwarded: _toNum(j['total_awarded']),
      totalMax: _toNum(j['total_max']),
      percentage: _toNum(j['percentage']),
      strengths: strings(j['strengths']),
      priorities: strings(j['priorities']),
      target: j['target']?.toString(),
      exam: j['exam'] is Map
          ? MarkingExam.fromJson(Map<String, dynamic>.from(j['exam'] as Map))
          : null,
    );
  }

  @override
  List<Object?> get props => [
        parts,
        totalAwarded,
        totalMax,
        percentage,
        strengths,
        priorities,
        target,
        exam,
      ];
}

/// One uploaded file on a submission.
class SubmissionFile extends Equatable {
  const SubmissionFile({required this.name, this.path, this.size, this.mime});

  final String name;
  final String? path;
  final int? size;
  final String? mime;

  factory SubmissionFile.fromJson(Map<String, dynamic> j) => SubmissionFile(
        name: (j['file_name'] ?? j['name'] ?? j['filename'] ?? '').toString(),
        path: (j['file_path'] ?? j['path'] ?? j['url'])?.toString(),
        size: _toInt(j['size'] ?? j['file_size']),
        mime: (j['mime'] ?? j['content_type'])?.toString(),
      );

  @override
  List<Object?> get props => [name, path, size, mime];
}

/// The student-safe submission shape (API_BRIEF §7).
///
/// The backend whitelists these fields on purpose — the raw document carries
/// marker-only data. Critically:
///
///   * When [released] is false, `grade` and `feedback` are **absent from the
///     payload** and `marking` / `annotated_url` are null. An absent mark is
///     not a zero — show "awaiting release" and no number.
///   * When [released] is true, the mark, feedback and full breakdown appear.
class Submission extends Equatable {
  const Submission({
    required this.id,
    required this.assignmentId,
    required this.status,
    this.submittedAt,
    this.gradedAt,
    this.released = false,
    this.textContent,
    this.answerText,
    this.files = const [],
    this.fileName,
    this.filePath,
    this.grade,
    this.feedback,
    this.annotatedUrl,
    this.marking,
  });

  final String id;
  final String assignmentId;
  final String status;
  final DateTime? submittedAt;
  final DateTime? gradedAt;

  /// Whether the teacher has released the mark to the student.
  final bool released;

  final String? textContent;
  final String? answerText;
  final List<SubmissionFile> files;
  final String? fileName;
  final String? filePath;

  /// Present only when [released]. Null means "not released yet", never zero.
  final num? grade;
  final String? feedback;
  final String? annotatedUrl;
  final Marking? marking;

  /// True when the work is marked but the mark is being withheld.
  bool get awaitingRelease => status == 'graded' && !released;

  /// Only show a number when the server actually sent one.
  bool get hasVisibleGrade => released && grade != null;

  factory Submission.fromJson(Map<String, dynamic> j) {
    final files = (j['files'] as List?)
            ?.whereType<Map>()
            .map((m) => SubmissionFile.fromJson(Map<String, dynamic>.from(m)))
            .toList() ??
        const <SubmissionFile>[];
    return Submission(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      assignmentId: (j['assignment_id'] ?? '').toString(),
      status: (j['status'] ?? 'submitted').toString(),
      submittedAt: _toDate(j['submitted_at']),
      gradedAt: _toDate(j['graded_at']),
      // Absent `released` means the backend did not mark it released.
      released: j['released'] == true,
      textContent: j['text_content']?.toString(),
      answerText: j['answer_text']?.toString(),
      files: files,
      fileName: j['file_name']?.toString(),
      filePath: j['file_path']?.toString(),
      // `grade` is REMOVED from the payload when not released — reading it
      // with a `?? 0` fallback would invent a zero the student never got.
      grade: _toNum(j['grade']),
      feedback: j['feedback']?.toString(),
      annotatedUrl: j['annotated_url']?.toString(),
      marking: j['marking'] is Map
          ? Marking.fromJson(Map<String, dynamic>.from(j['marking'] as Map))
          : null,
    );
  }

  @override
  List<Object?> get props => [
        id,
        assignmentId,
        status,
        submittedAt,
        gradedAt,
        released,
        textContent,
        answerText,
        files,
        fileName,
        filePath,
        grade,
        feedback,
        annotatedUrl,
        marking,
      ];
}

/// Homework and quizzes share one `assignments` collection, separated by
/// `type` (API_BRIEF §7).
class Assignment extends Equatable {
  const Assignment({
    required this.id,
    required this.title,
    required this.type, // homework|quiz
    this.subjectId,
    this.subjectName,
    this.description,
    this.dueAt,
    this.createdAt,
    this.status,
    this.states = const [],
    this.submission,
    this.maxScore,
    this.attachmentUrl,
    this.attachmentFilename,
    this.attachmentMime,
    this.attachmentSize,
  });

  final String id;
  final String title;
  final String type;
  final String? subjectId;
  final String? subjectName;
  final String? description;
  final DateTime? dueAt;
  final DateTime? createdAt;

  /// `submission_status`: the collapsed state, by precedence
  /// `graded > submitted > overdue > pending`.
  final String? status;

  /// `submission_states`: the full set, in a stable render order. `late` is an
  /// adjective that rides alongside `submitted` — render both chips.
  final List<String> states;

  final Submission? submission;
  final num? maxScore;

  /// Token-protected path: `/api/v1/student/assignments/<id>/attachment`.
  /// Fetch it through the authenticated Dio client — never `Image.network`,
  /// a bare WebView, or an external browser.
  final String? attachmentUrl;
  final String? attachmentFilename;
  final String? attachmentMime;
  final int? attachmentSize;

  /// Valid values of `submission_status` per API_BRIEF §7. `late` is NOT one
  /// of them — it only ever appears inside `submission_states`.
  static const validStatuses = {'graded', 'submitted', 'overdue', 'pending'};

  bool get isLate => states.contains('late');
  bool get isSubmitted => status == 'submitted' || status == 'graded';
  bool get isGraded => status == 'graded';

  /// True when the server said `overdue`, or — if it sent no status at all —
  /// the due date has passed with nothing submitted.
  ///
  /// The server's `submission_status` is authoritative when present; the date
  /// fallback only covers payloads that omit it.
  bool get isOverdue {
    if (status == 'overdue') return true;
    if (status != null) return false;
    final due = dueAt;
    if (due == null) return false;
    return DateTime.now().isAfter(due);
  }

  /// Resubmission is allowed right up until the work is graded.
  bool get canResubmit => status != 'graded';

  /// Marked, but the teacher has not released the mark. Show "awaiting
  /// release" and no number.
  bool get awaitingRelease => isGraded && !(submission?.released ?? false);

  /// The mark to display, or null when there is nothing to show yet.
  num? get visibleGrade =>
      submission?.hasVisibleGrade == true ? submission!.grade : null;

  factory Assignment.fromJson(Map<String, dynamic> j) {
    // The detail route nests the assignment under `assignment` and puts the
    // submission alongside it; the list route returns them flat on one object.
    final root = j['assignment'] is Map
        ? Map<String, dynamic>.from(j['assignment'] as Map)
        : j;
    final submissionJson = j['submission'] is Map
        ? Map<String, dynamic>.from(j['submission'] as Map)
        : (root['submission'] is Map
            ? Map<String, dynamic>.from(root['submission'] as Map)
            : null);
    final submission =
        submissionJson == null ? null : Submission.fromJson(submissionJson);

    final states =
        (j['submission_states'] ?? root['submission_states']) as List?;
    final stateList = states
            ?.map((e) => e?.toString() ?? '')
            .where((e) => e.isNotEmpty)
            .toList() ??
        const <String>[];

    // Take `submission_status` verbatim when the server sent a valid one.
    // Never coerce `overdue` away — it is a real state, and dropping it makes
    // an overdue item render as "Pending".
    var status =
        (j['submission_status'] ?? root['submission_status'])?.toString();
    if (status != null && !validStatuses.contains(status)) status = null;
    status ??= _collapseStates(stateList);
    if (status == null && submission != null) {
      status = submission.status == 'graded' ? 'graded' : 'submitted';
    }

    return Assignment(
      id: (root['_id'] ?? root['id'] ?? '').toString(),
      title: (root['title'] ?? root['name'] ?? '').toString(),
      type: (root['type'] ?? 'homework').toString(),
      subjectId: (root['class_id'] ?? root['subject_id'])?.toString(),
      subjectName: (root['class_name'] ?? root['subject_name'])?.toString(),
      description: root['description']?.toString(),
      dueAt: _toDate(root['due_at'] ?? root['due_date']),
      createdAt: _toDate(root['created_at']),
      status: status,
      states: stateList,
      submission: submission,
      maxScore: _toNum(root['max_score'] ?? root['total_score']),
      attachmentUrl: (root['attachment_url'] ??
              (root['attachment'] is Map ? root['attachment']['url'] : null))
          ?.toString(),
      attachmentFilename: root['attachment_filename']?.toString(),
      attachmentMime: root['attachment_mime']?.toString(),
      attachmentSize: _toInt(root['attachment_size']),
    );
  }

  /// Mirrors the server's precedence `graded > submitted > overdue > pending`
  /// (backend `services/submission_state.py`). Used only as a fallback when
  /// `submission_status` was absent.
  static String? _collapseStates(List<String> states) {
    for (final s in ['graded', 'submitted', 'overdue', 'pending']) {
      if (states.contains(s)) return s;
    }
    return null;
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
        createdAt,
        status,
        states,
        submission,
        maxScore,
        attachmentUrl,
        attachmentFilename,
        attachmentMime,
        attachmentSize,
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
  bool get isComplete => videos.isNotEmpty && videos.every((v) => v.completed);

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

/// `GET /student/subjects` returns the list plus the echoed filters and the
/// bucket counts (API_BRIEF §5) — the counts drive the filter chip badges.
class SubjectsPage extends Equatable {
  const SubjectsPage({
    this.subjects = const [],
    this.filter,
    this.grade,
    this.examBoard,
    this.total = 0,
    this.enrolled = 0,
    this.pending = 0,
    this.available = 0,
  });

  final List<Subject> subjects;

  /// Echoed back by the server so the UI can confirm what it actually applied.
  final String? filter;
  final int? grade;
  final String? examBoard;

  final int total;
  final int enrolled;
  final int pending;
  final int available;

  factory SubjectsPage.fromJson(Map<String, dynamic> j) {
    final filters = j['filters'] is Map
        ? Map<String, dynamic>.from(j['filters'] as Map)
        : const <String, dynamic>{};
    final counts = j['counts'] is Map
        ? Map<String, dynamic>.from(j['counts'] as Map)
        : const <String, dynamic>{};
    return SubjectsPage(
      subjects: (j['subjects'] as List?)
              ?.whereType<Map>()
              .map((m) => Subject.fromJson(Map<String, dynamic>.from(m)))
              .toList() ??
          const [],
      filter: filters['filter']?.toString(),
      grade: _toInt(filters['grade']),
      examBoard: filters['exam_board']?.toString(),
      total: _toInt(counts['total']) ?? 0,
      enrolled: _toInt(counts['enrolled']) ?? 0,
      pending: _toInt(counts['pending']) ?? 0,
      available: _toInt(counts['available']) ?? 0,
    );
  }

  @override
  List<Object?> get props =>
      [subjects, filter, grade, examBoard, total, enrolled, pending, available];
}

/// `GET /notifications` returns `{ notifications: [...], unread_count: n }`
/// (API_BRIEF §9). The count is authoritative — do not recompute it from the
/// page, which is capped at 50 rows.
class NotificationsPage extends Equatable {
  const NotificationsPage({this.items = const [], this.unreadCount = 0});

  final List<NotificationItem> items;
  final int unreadCount;

  factory NotificationsPage.fromJson(Map<String, dynamic> j) =>
      NotificationsPage(
        items: (j['notifications'] as List?)
                ?.whereType<Map>()
                .map(
                  (m) =>
                      NotificationItem.fromJson(Map<String, dynamic>.from(m)),
                )
                .toList() ??
            const [],
        unreadCount: _toInt(j['unread_count']) ?? 0,
      );

  @override
  List<Object?> get props => [items, unreadCount];
}

/// A file fetched from a token-protected route (assignment attachment or the
/// annotated `graded.pdf`).
///
/// Held in memory deliberately: these routes require an `Authorization`
/// header, so the bytes cannot be handed to a plain URL loader, and writing
/// them to shared storage would put marked work outside the app sandbox.
class AssignmentFile {
  const AssignmentFile({
    required this.bytes,
    required this.filename,
    this.mime,
  });

  final Uint8List bytes;
  final String filename;
  final String? mime;

  bool get isPdf =>
      mime?.contains('pdf') == true || filename.toLowerCase().endsWith('.pdf');

  bool get isImage => mime?.startsWith('image/') == true;

  int get sizeBytes => bytes.length;
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
