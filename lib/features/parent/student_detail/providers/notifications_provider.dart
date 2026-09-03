import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/app_env.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/providers.dart';
import '../models/activity_notification.dart';

final notificationsProvider =
    FutureProvider.family.autoDispose<List<ActivityNotification>, String>(
        (ref, studentId) async {
  final api = ref.read(apiClientProvider);
  final v1 = AppEnv.I.apiV1Prefix;
  try {
    final res = await api.dio
        .get<dynamic>('$v1/parent/students/$studentId/notifications');
    final body = res.data;
    if (body is! Map) throw const FormatException('Bad response');
    if (body['success'] != true) {
      final err = body['error'];
      throw ErrorMapper.fromObject(
          (err is Map ? err['message'] : null) ?? 'Failed to load');
    }
    final data = body['data'];
    if (data is! Map) return const <ActivityNotification>[];
    final list = (data['notifications'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) =>
            ActivityNotification.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  } on DioException catch (e) {
    throw ErrorMapper.fromDio(e);
  }
});

/// Locally-marked-read notification IDs (per student). Persists only in memory.
class _LocalReadIds extends StateNotifier<Set<String>> {
  _LocalReadIds() : super(const <String>{});
  void markRead(String id) => state = {...state, id};
}

final notificationLocalReadProvider = StateNotifierProvider.family
    .autoDispose<_LocalReadIds, Set<String>, String>(
        (ref, studentId) => _LocalReadIds());
