import 'package:dio/dio.dart';

import '../../core/env/app_env.dart';
import '../../core/error/error_mapper.dart';
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

  Future<List<Subject>> subjects({
    String? filter,
    int? grade,
    String? examBoard,
  }) =>
      _getList<Subject>(
        ['$_v1/student/subjects'],
        Subject.fromJson,
        query: {
          if (filter != null) 'filter': filter,
          if (grade != null) 'grade': grade,
          if (examBoard != null) 'exam_board': examBoard,
        },
      );

  Future<Subject> subject(String id) => _get<Subject>(
        ['$_v1/student/subjects/$id'],
        Subject.fromJson,
      );

  Future<List<Subject>> publicSubjects() => _getList<Subject>(
        ['$_v1/student/subjects'],
        Subject.fromJson,
      );

  // ---------- Enrollments ----------

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

  Future<List<ContentItem>> contents() => _getList<ContentItem>(
        ['$_v1/student/content'],
        ContentItem.fromJson,
      );

  Future<ContentEmbed> contentEmbed(String contentId) => _get<ContentEmbed>(
        ['$_v1/student/content/$contentId/embed'],
        ContentEmbed.fromJson,
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

  Future<void> sendHeartbeat({
    required String contentId,
    required String classOrSubjectId,
    required int deltaSeconds,
    required int currentPositionSeconds,
    required bool tabVisible,
  }) async {
    try {
      await _client.dio.post<dynamic>(
        '$_v1/student/watch-heartbeat',
        data: {
          'content_id': contentId,
          'class_id': classOrSubjectId,
          'delta': deltaSeconds,
          'current_position': currentPositionSeconds,
          'tab_visible': tabVisible,
        },
      );
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  // ---------- Progress ----------

  Future<SubjectProgress> progress(String subjectId) => _get<SubjectProgress>(
        ['$_v1/student/progress/$subjectId'],
        SubjectProgress.fromJson,
      );

  // ---------- Cloudflare Stream videos (new pipeline) ----------

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

  /// Security telemetry — fire-and-forget. The backend alerts on threshold
  /// breaches (screenshot, recording, mirroring, jailbreak, etc).
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

  Future<List<Assignment>> assignments({
    String? type,
    String? status,
    int page = 1,
    int limit = 20,
  }) =>
      _getList<Assignment>(
        ['$_v1/student/assignments'],
        Assignment.fromJson,
        query: {
          if (type != null) 'type': type,
          if (status != null) 'status': status,
          'page': page,
          'limit': limit,
        },
      );

  Future<Assignment> assignment(String id) => _get<Assignment>(
        ['$_v1/student/assignments/$id'],
        Assignment.fromJson,
      );

  Future<List<Assignment>> quizzes({int page = 1, int limit = 20}) =>
      _getList<Assignment>(
        ['$_v1/student/quizzes'],
        Assignment.fromJson,
        query: {'page': page, 'limit': limit},
      );

  Future<Assignment> submitAssignment({
    required String id,
    String? textContent,
    MultipartFile? attachment,
  }) async {
    try {
      final form = FormData.fromMap({
        if (textContent != null) 'text_content': textContent,
        if (attachment != null) 'attachment': attachment,
      });
      final res = await _client.dio.post<dynamic>(
        '$_v1/student/assignments/$id/submit',
        data: form,
      );
      final env = ApiEnvelope.from<Map<String, dynamic>>(
        res.data,
        (j) => Map<String, dynamic>.from(j as Map),
      );
      return env.data != null
          ? Assignment.fromJson(env.data!)
          : await assignment(id);
    } on DioException catch (e) {
      throw ErrorMapper.fromDio(e);
    }
  }

  // ---------- Announcements ----------

  Future<List<Announcement>> announcements(
          {String scope = 'global', String? scopeId}) =>
      _getList<Announcement>(
        ['$_v1/announcements'],
        Announcement.fromJson,
        query: {'scope': scope, if (scopeId != null) 'id': scopeId},
      );

  // ---------- Notifications ----------

  Future<List<NotificationItem>> notifications() => _getList<NotificationItem>(
        ['$_v1/notifications'],
        NotificationItem.fromJson,
      );

  Future<List<NotificationItem>> notificationsLatest() =>
      _getList<NotificationItem>(
        ['$_v1/notifications/latest'],
        NotificationItem.fromJson,
      );

  Future<void> markNotificationRead({String? notificationId}) async {
    try {
      await _client.dio.post<dynamic>(
        notificationId == null
            ? '$_v1/notifications/mark-all-read'
            : '$_v1/notifications/mark-read',
        data:
            notificationId == null ? null : {'notification_id': notificationId},
      );
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
