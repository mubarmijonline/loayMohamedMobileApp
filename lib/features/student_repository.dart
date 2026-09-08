import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/env/app_env.dart';
import '../../core/error/error_mapper.dart';
import '../../core/error/failures.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_envelope.dart';
import '_shared/models.dart';

/// Single repository covering all student endpoints. Kept cohesive because the
/// student API is one bounded context and most calls share auth/error handling.
class StudentRepository {
  StudentRepository(this._client);
  final ApiClient _client;

  String get _v1 => AppEnv.I.apiV1Prefix;

  /// New Cloudflare Stream surface lives outside the /v1 namespace.
  /// Keep this constant so the path is easy to point at a different prefix
  /// later if the backend reshuffles.
  static const _streamPrefix = '/api/student';

  /// Security telemetry endpoint (see SecureStreamPlayer).
  static const _securityEventPath = '/api/security/event';

  // ---------- Dashboard / Subjects ----------

  Future<StudentDashboard> dashboard() => _get<StudentDashboard>(
        ['$_v1/student/dashboard'],
        StudentDashboard.fromJson,
      );

  /// `GET /student/subjects` — the full page, including `counts` and the
  /// echoed `filters` (API_BRIEF §5). `filter=available` excludes both
  /// enrolled and pending items.
  Future<SubjectsPage> subjectsPage({
    String? filter,
    int? grade,
    String? examBoard,
  }) =>
      _get<SubjectsPage>(
        ['$_v1/student/subjects'],
        SubjectsPage.fromJson,
        query: {
          if (filter != null) 'filter': filter,
          if (grade != null) 'grade': grade,
          if (examBoard != null) 'exam_board': examBoard,
        },
      );

  Future<List<Subject>> subjects({
    String? filter,
    int? grade,
    String? examBoard,
  }) async =>
      (await subjectsPage(filter: filter, grade: grade, examBoard: examBoard))
          .subjects;

  /// Subject detail, resolved from the **list** response.
  ///
  /// `GET /student/subjects/<id>` is broken server-side (API_BRIEF §13.1): the
  /// list route reads `teacher_classes` while the detail route reads the
  /// `subjects` collection, so an id taken from the list always 404s there.
  /// Until that is fixed, detail is rendered from the object already in hand.
  ///
  /// Do not "fix" this by calling the detail endpoint — it will 404.
  Future<Subject> subject(String id) async {
    final page = await subjectsPage();
    for (final s in page.subjects) {
      if (s.id == id) return s;
    }
    throw const NotFoundFailure('This subject is no longer available.');
  }

  Future<List<Subject>> publicSubjects() => subjects();

  // ---------- Enrollments ----------

  /// `GET /student/enrollments`.
  ///
  /// NOTE (API_BRIEF §13.2): `subject_title` is **always empty** — the backend
  /// reads `.title` off a `teacher_classes` document, and those store `name`.
  /// Resolve the display name from [subjects] instead of trusting this field.
  Future<List<Enrollment>> enrollments() => _getList<Enrollment>(
        ['$_v1/student/enrollments'],
        Enrollment.fromJson,
      );

  Future<Enrollment> requestEnrollment(String subjectId) async {
    try {
      final res = await _client.dio.post<dynamic>(
        '$_v1/student/enrollment-requests',
        data: {'subject_id': subjectId},
      );
      final env = ApiEnvelope.from<Map<String, dynamic>>(
        res.data,
        (j) => Map<String, dynamic>.from(j as Map),
      );
      if (!env.success || env.data == null) {
        return Enrollment(id: '', subjectId: subjectId, status: 'pending');
      }
      return Enrollment.fromJson(env.data!);
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  // ---------- Lessons / Content ----------

  Future<List<Lesson>> lessons(String subjectId) => _getList<Lesson>(
        ['$_v1/student/subjects/$subjectId/lessons'],
        Lesson.fromJson,
      );

  Future<ContentItem> content(String contentId) => _get<ContentItem>(
        ['$_v1/student/content/$contentId'],
        ContentItem.fromJson,
      );

  /// `GET /student/content` — every visible item across the student's active
  /// classes.
  ///
  /// **Already sorted by `(class_id, group_title, order_index, created_at)`**,
  /// the same order the portal returns. Preserve it: `ContentSection.group`
  /// walks the list once and breaks sections on change. Re-sorting here would
  /// make the two clients disagree about section order.
  Future<List<ContentItem>> contents() => _getList<ContentItem>(
        ['$_v1/student/content'],
        ContentItem.fromJson,
      );

  /// `GET /student/classes` — per-class progress, for the Videos screen
  /// section headers and the "6/10 watched" pill.
  Future<List<StudentClass>> classes() => _getList<StudentClass>(
        ['$_v1/student/classes'],
        StudentClass.fromJson,
      );

  /// Fetches a content thumbnail through the authenticated client.
  ///
  /// `thumbnail_url` is `/api/v1/student/content/<id>/thumbnail`, which is NOT
  /// public — an `Image.network` cannot attach the bearer token and gets a
  /// 401. Returns null rather than throwing: a missing poster is a cosmetic
  /// problem, not a reason to fail the list.
  Future<Uint8List?> contentThumbnail(String contentId) async {
    try {
      final res = await _client.dio.get<List<int>>(
        '$_v1/student/content/$contentId/thumbnail',
        options: Options(
          responseType: ResponseType.bytes,
          // The route 302s to Cloudflare / stored URLs for some providers.
          followRedirects: true,
        ),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) return null;
      return Uint8List.fromList(bytes);
    } on DioException {
      return null;
    }
  }

  /// `stream_url` comes back as a path, not a URL. Dio would resolve it
  /// against `baseUrl`; the players cannot, so it is resolved here — once, at
  /// the boundary — rather than in two player widgets that would each have to
  /// remember to.
  Future<ContentEmbed> contentEmbed(String contentId) => _get<ContentEmbed>(
        ['$_v1/student/content/$contentId/embed'],
        (j) => ContentEmbed.fromJson(j).resolvedAgainst(AppEnv.I.apiBaseUrl),
      );

  Future<ResumeState> contentResume(String contentId) => _get<ResumeState>(
        ['$_v1/student/content/$contentId/resume'],
        ResumeState.fromJson,
      );

  Future<void> sendWatchEvent({
    required String subjectId,
    String? lessonId,
    required String contentId,
    required int watchedSecondsDelta,
    required bool tabVisible,
    double playbackRate = 1.0,
  }) async {
    try {
      await _client.dio.post<dynamic>(
        '$_v1/student/watch-events',
        data: {
          'subject_id': subjectId,
          if (lessonId != null && lessonId.isNotEmpty) 'lesson_id': lessonId,
          'content_id': contentId,
          'watched_seconds_delta': watchedSecondsDelta,
          'tab_visible': tabVisible,
          'playback_rate': playbackRate,
        },
      );
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  /// `POST /student/watch-heartbeat` — the tracker the app should use
  /// (API_BRIEF §6).
  ///
  /// Body is exactly `{ content_id, delta, current_position, tab_visible }`.
  /// [deltaSeconds] is real elapsed *play* time since the last beat: the
  /// server clamps it to 0..60 but does not validate it, so an inflated delta
  /// silently corrupts teacher reports. Never send a beat for time spent
  /// paused, backgrounded, or under the capture-blackout overlay.
  ///
  /// Returns the server's running `total_watched`, or null if it did not say.
  Future<int?> sendHeartbeat({
    required String contentId,
    required int deltaSeconds,
    required int currentPositionSeconds,
    required bool tabVisible,
  }) async {
    // Mirror the server-side clamp so a bad local clock cannot post garbage.
    final delta = deltaSeconds.clamp(0, 60);
    if (delta <= 0) return null; // Server writes nothing for delta <= 0.
    try {
      final res = await _client.dio.post<dynamic>(
        '$_v1/student/watch-heartbeat',
        data: {
          'content_id': contentId,
          'delta': delta,
          'current_position':
              currentPositionSeconds < 0 ? 0 : currentPositionSeconds,
          'tab_visible': tabVisible,
        },
      );
      final body = res.data;
      if (body is Map) {
        final d = body['data'] is Map ? body['data'] as Map : body;
        final v = d['total_watched'];
        return v is num ? v.toInt() : null;
      }
      return null;
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  // ---------- Progress ----------

  Future<SubjectProgress> progress(String subjectId) => _get<SubjectProgress>(
        ['$_v1/student/progress/$subjectId'],
        SubjectProgress.fromJson,
      );

  // ---------- Cloudflare Stream videos (LEGACY / UNVERIFIED) ----------
  //
  // WARNING: none of the `/api/student/*` routes below, nor
  // `/api/security/event`, appear anywhere in `docs/mobile/API_BRIEF.md`,
  // which was verified against the backend source on 2026-09-04 and
  // supersedes the older `MOBILE_API_ENDPOINTS.txt` (see §13.6).
  //
  // Treat them as unavailable until the backend team confirms otherwise:
  //  * Video playback goes through `/student/content/<id>/embed` (§6).
  //  * Watch tracking goes through `/student/watch-heartbeat` (§6).
  //  * There is NO capture-report endpoint — screenshot/recording events must
  //    be queued locally, not posted (see ScreenGuard).
  //
  // Callers should expect 404. Do not build new screens on these.

  /// Lists every video assigned to [classId], grouped by `group_title`.
  /// Backend filters out `is_visible=false` rows and expired enrollments.
  Future<ClassVideos> classVideos(String classId) async {
    try {
      final res = await _client.dio
          .get<dynamic>('$_streamPrefix/classes/$classId/videos');
      final body = res.data;
      // The endpoint returns `{ ok, class, groups }` directly, not the
      // {success, data:{}} envelope the v1 namespace uses.
      if (body is Map<String, dynamic> &&
          (body['ok'] == true || body['success'] == true)) {
        return ClassVideos.fromJson(body);
      }
      if (body is Map) {
        return ClassVideos.fromJson(Map<String, dynamic>.from(body));
      }
      throw ErrorMapper.fromObject('Malformed videos response');
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  /// Mints a fresh signed playback ticket for [videoId]. The returned URLs
  /// expire (see [PlaybackTicket.expiresAt]); callers MUST refresh before use
  /// after resuming from background.
  Future<PlaybackTicket> videoPlayback(String videoId) async {
    try {
      final res = await _client.dio
          .post<dynamic>('$_streamPrefix/videos/$videoId/playback');
      final body = res.data;
      if (body is Map) {
        final map = Map<String, dynamic>.from(body);
        if (map['ok'] == false || map['success'] == false) {
          final err = map['error'];
          throw ErrorMapper.fromObject(
            (err is Map ? err['message'] : null) ?? 'Playback unavailable',
          );
        }
        return PlaybackTicket.fromJson(map);
      }
      throw ErrorMapper.fromObject('Malformed playback response');
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  /// Reports playback progress for [videoId]. Sent every 15 s as a `tick`,
  /// once as `completed` when position/duration ≥ 0.9, and once as `pause`
  /// on dispose / background.
  Future<void> videoProgress({
    required String videoId,
    required int positionSeconds,
    required int durationSeconds,
    required String event, // 'tick' | 'completed' | 'pause'
  }) async {
    try {
      await _client.dio.post<dynamic>(
        '$_streamPrefix/videos/$videoId/progress',
        data: {
          'position': positionSeconds,
          'duration': durationSeconds,
          'event': event,
        },
      );
    } on DioException {
      // Best-effort — next tick will retry.
    }
  }

  /// Security telemetry — fire-and-forget.
  ///
  /// NOT IN THE API BRIEF. There is no capture-report route in the verified
  /// contract; this will 404 until the backend adds one. Events are queued by
  /// `ScreenGuard` locally and this is only attempted opportunistically.
  @Deprecated('No such endpoint in API_BRIEF. Pending backend work.')
  Future<void> postSecurityEvent({
    required String event,
    String? videoId,
    Map<String, dynamic>? deviceInfo,
  }) async {
    try {
      await _client.dio.post<dynamic>(
        _securityEventPath,
        data: {
          'event': event,
          if (videoId != null) 'video_id': videoId,
          if (deviceInfo != null) 'device_info': deviceInfo,
        },
      );
    } on DioException {
      // Telemetry is best-effort; never fail the player on this.
    }
  }

  // ---------- Assignments / Quizzes ----------

  /// `GET /student/assignments` — optionally filtered by `type`.
  ///
  /// `type` is the **only** query parameter this route accepts (API_BRIEF §7).
  /// The `status`, `page` and `limit` params documented in the old
  /// `MOBILE_API_ENDPOINTS.txt` do not exist; the route is unpaginated.
  /// Filter by state client-side on `submission_status`.
  Future<List<Assignment>> assignments({String? type}) => _getList<Assignment>(
        ['$_v1/student/assignments'],
        Assignment.fromJson,
        query: {if (type != null) 'type': type},
      );

  /// `GET /student/assignments/<id>` — returns `{ assignment, submission }`.
  /// [Assignment.fromJson] flattens both shapes.
  Future<Assignment> assignment(String id) => _get<Assignment>(
        ['$_v1/student/assignments/$id'],
        Assignment.fromJson,
      );

  /// `GET /student/quizzes` — identical to `assignments(type: 'quiz')`.
  Future<List<Assignment>> quizzes() => _getList<Assignment>(
        ['$_v1/student/quizzes'],
        Assignment.fromJson,
      );

  /// `POST /student/assignments/<id>/submit` (API_BRIEF §7).
  ///
  /// Sent as `multipart/form-data`, which is the only encoding that accepts
  /// files. **Multiple files are accepted** under `attachments[]`; the first
  /// is mirrored into the legacy `file_path` / `file_name` fields server-side.
  ///
  /// [answers] is serialised to a JSON **string** — the server parses it and
  /// returns `400 invalid_answers` if it is malformed.
  ///
  /// At least one of text / answers / files is required, else
  /// `400 empty_submission`. Resubmission is allowed until the work is graded
  /// (`409 already_graded` after that).
  ///
  /// The route responds `{ created: true }` / `{ updated: true }` — not an
  /// assignment — so the fresh state is re-read before returning.
  Future<Assignment> submitAssignment({
    required String id,
    String? textContent,
    Map<String, dynamic>? answers,
    List<MultipartFile> attachments = const [],
  }) async {
    final hasText = textContent != null && textContent.trim().isNotEmpty;
    final hasAnswers = answers != null && answers.isNotEmpty;
    if (!hasText && !hasAnswers && attachments.isEmpty) {
      throw const ValidationFailure(
        'Add an answer, a file, or some text before submitting.',
        code: 'empty_submission',
      );
    }
    try {
      final form = FormData();
      if (hasText) {
        form.fields.add(MapEntry('text_content', textContent));
      }
      if (hasAnswers) {
        form.fields.add(MapEntry('answers', jsonEncode(answers)));
      }
      for (final file in attachments) {
        form.files.add(MapEntry('attachments[]', file));
      }
      await _client.dio.post<dynamic>(
        '$_v1/student/assignments/$id/submit',
        data: form,
      );
      // Response is a bare `{created|updated: true}` flag; re-read for state.
      return await assignment(id);
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  /// `GET /student/assignments/<id>/attachment` — the teacher's brief.
  ///
  /// This path is **token-protected**: it must be fetched through the
  /// authenticated client. Handing it to `Image.network`, a bare WebView, or
  /// an external browser sends no `Authorization` header and gets a 401.
  Future<AssignmentFile> assignmentAttachment(String id) =>
      _download('$_v1/student/assignments/$id/attachment');

  /// `GET /student/assignments/<id>/graded.pdf` — the AI-annotated script.
  ///
  /// Served only once the teacher approves it: `404 no_annotated` before it is
  /// rendered, `403 not_released` while the mark is still withheld.
  Future<AssignmentFile> gradedPdf(String id) =>
      _download('$_v1/student/assignments/$id/graded.pdf');

  Future<AssignmentFile> _download(String path) async {
    try {
      final res = await _client.dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) {
        throw const NotFoundFailure('This file is not available.');
      }
      return AssignmentFile(
        bytes: Uint8List.fromList(bytes),
        filename: _filenameFrom(res.headers.value('content-disposition')) ??
            path.split('/').last,
        mime: res.headers.value('content-type'),
      );
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  /// Pulls `filename="..."` out of a Content-Disposition header.
  static String? _filenameFrom(String? header) {
    if (header == null) return null;
    final m =
        RegExp(r'filename\*?=(?:UTF-8' ')?"?([^";]+)"?').firstMatch(header);
    final name = m?.group(1)?.trim();
    if (name == null || name.isEmpty) return null;
    return Uri.decodeComponent(name);
  }

  // ---------- Announcements ----------

  Future<List<Announcement>> announcements({
    String scope = 'global',
    String? scopeId,
  }) =>
      _getList<Announcement>(
        ['$_v1/announcements'],
        Announcement.fromJson,
        query: {'scope': scope, if (scopeId != null) 'id': scopeId},
      );

  // ---------- Notifications ----------

  /// `GET /notifications` — `{ notifications: [...], unread_count: n }`,
  /// capped at 50 rows, newest first (API_BRIEF §9).
  Future<NotificationsPage> notificationsPage() => _get<NotificationsPage>(
        ['$_v1/notifications'],
        NotificationsPage.fromJson,
      );

  Future<List<NotificationItem>> notifications() async =>
      (await notificationsPage()).items;

  /// `GET /notifications/latest` — **a single object or null**, not a list
  /// (API_BRIEF §9). Returns the most recent *unread* notification.
  Future<NotificationItem?> notificationsLatest() async {
    try {
      final res = await _client.dio.get<dynamic>('$_v1/notifications/latest');
      final body = res.data;
      Object? data = body;
      if (body is Map && body.containsKey('success')) {
        if (body['success'] != true) {
          final err = body['error'];
          throw ErrorMapper.fromObject(
            (err is Map ? err['message'] : null) ?? 'Request failed',
          );
        }
        data = body['data'];
      }
      if (data is! Map) return null; // null payload = nothing unread.
      return NotificationItem.fromJson(Map<String, dynamic>.from(data));
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  /// Marks a **single** notification read.
  ///
  /// DANGER (API_BRIEF §13.4): `POST /notifications/mark-read` with no
  /// `notification_id` silently marks *everything* read. This method refuses
  /// to send an empty id — use [markAllNotificationsRead] when the user
  /// actually tapped "mark all read".
  Future<void> markNotificationRead(String notificationId) async {
    if (notificationId.trim().isEmpty) {
      throw ArgumentError(
        'notification_id is required: an empty id silently marks every '
        'notification read. Call markAllNotificationsRead() instead.',
      );
    }
    try {
      await _client.dio.post<dynamic>(
        '$_v1/notifications/mark-read',
        data: {'notification_id': notificationId},
      );
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  /// `POST /notifications/mark-all-read` — the explicit, dedicated route.
  Future<void> markAllNotificationsRead() async {
    try {
      await _client.dio.post<dynamic>('$_v1/notifications/mark-all-read');
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  // ---------- Push device registration ----------

  Future<void> registerPushDevice({
    required String oneSignalPlayerId,
    required String platform,
    String? appVersion,
    String? deviceModel,
    String? osVersion,
    String? role,
  }) async {
    try {
      await _client.dio.post<dynamic>(
        '$_v1/devices/register',
        data: {
          'player_id': oneSignalPlayerId,
          'platform': platform,
          if (appVersion != null) 'app_version': appVersion,
          if (deviceModel != null) 'device_model': deviceModel,
          if (osVersion != null) 'os_version': osVersion,
          if (role != null) 'role': role,
        },
      );
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  Future<void> unregisterPushDevice(String oneSignalPlayerId) async {
    try {
      await _client.dio.delete<dynamic>(
        '$_v1/devices/$oneSignalPlayerId',
      );
    } on DioException {
      // Best-effort — do not fail logout.
    }
  }

  // ---------- helpers ----------

  Future<T> _get<T>(
    List<String> paths,
    T Function(Map<String, dynamic>) parser, {
    Map<String, dynamic>? query,
  }) async {
    DioException? lastErr;
    for (final p in paths) {
      try {
        final res = await _client.dio.get<dynamic>(p, queryParameters: query);
        final env = ApiEnvelope.from<Map<String, dynamic>>(
          res.data,
          (j) => Map<String, dynamic>.from(j as Map),
        );
        if (!env.success) {
          throw ErrorMapper.fromObject(env.errorMessage ?? 'Request failed');
        }
        if (env.data == null) {
          throw ErrorMapper.fromObject('Empty response');
        }
        return parser(env.data!);
      } on DioException catch (e) {
        lastErr = e;
        if (e.response?.statusCode != 404) {
          throw ErrorMapper.fromDio(e);
        }
      }
    }
    throw ErrorMapper.fromDio(lastErr!);
  }

  Future<List<T>> _getList<T>(
    List<String> paths,
    T Function(Map<String, dynamic>) parser, {
    Map<String, dynamic>? query,
  }) async {
    DioException? lastErr;
    for (final p in paths) {
      try {
        final res = await _client.dio.get<dynamic>(p, queryParameters: query);
        final body = res.data;
        Object? listData;
        if (body is Map) {
          if (body.containsKey('success') && body.containsKey('data')) {
            if (body['success'] != true) {
              final err = body['error'];
              throw ErrorMapper.fromObject(
                (err is Map ? err['message'] : null) ?? 'Request failed',
              );
            }
            final d = body['data'];
            if (d is List) {
              listData = d;
            } else if (d is Map && d['items'] is List) {
              listData = d['items'];
            } else if (d is Map && d['notifications'] is List) {
              listData = d['notifications'];
            } else if (d is Map && d['subjects'] is List) {
              listData = d['subjects'];
            } else if (d is Map && d['data'] is List) {
              listData = d['data'];
            } else {
              listData = d;
            }
          } else if (body['data'] is List) {
            listData = body['data'];
          } else if (body['items'] is List) {
            listData = body['items'];
          } else {
            listData = body;
          }
        } else {
          listData = body;
        }
        if (listData is! List) return const [];
        return listData
            .whereType<Map>()
            .map((m) => parser(Map<String, dynamic>.from(m)))
            .toList();
      } on DioException catch (e) {
        lastErr = e;
        if (e.response?.statusCode != 404) {
          throw ErrorMapper.fromDio(e);
        }
      }
    }
    throw ErrorMapper.fromDio(lastErr!);
  }
}
