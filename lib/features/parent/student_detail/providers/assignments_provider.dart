import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/app_env.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/providers.dart';
import '../models/assignment.dart';

/// Loads the assignment list for one student. Lazy: only fires when watched.
final assignmentsProvider =
    FutureProvider.family.autoDispose<List<Assignment>, String>(
        (ref, studentId) async {
  final api = ref.read(apiClientProvider);
  final v1 = AppEnv.I.apiV1Prefix;
  try {
    final res = await api.dio
        .get<dynamic>('$v1/parent/students/$studentId/assignments');
    final body = res.data;
    if (body is! Map) throw const FormatException('Bad response');
    if (body['success'] != true) {
      final err = body['error'];
      throw ErrorMapper.fromObject(
          (err is Map ? err['message'] : null) ?? 'Failed to load');
    }
    final data = body['data'];
    if (data is! Map) return const <Assignment>[];
    final list = (data['assignments'] as List?) ?? const [];
    return list
        .whereType<Map>()
        .map((m) => Assignment.fromJson(Map<String, dynamic>.from(m)))
        .toList();
  } on DioException catch (e) {
    throw ErrorMapper.fromDio(e);
  }
});
