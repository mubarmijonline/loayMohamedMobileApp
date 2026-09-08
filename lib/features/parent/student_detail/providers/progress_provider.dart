import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/env/app_env.dart';
import '../../../../core/error/error_mapper.dart';
import '../../../../core/providers.dart';
import '../models/progress.dart';

final progressProvider = FutureProvider.family
    .autoDispose<ProgressReport, String>((ref, studentId) async {
  final api = ref.read(apiClientProvider);
  final v1 = AppEnv.I.apiV1Prefix;
  try {
    final res =
        await api.dio.get<dynamic>('$v1/parent/students/$studentId/progress');
    final body = res.data;
    if (body is! Map) throw const FormatException('Bad response');
    if (body['success'] != true) {
      final err = body['error'];
      throw ErrorMapper.fromObject(
          (err is Map ? err['message'] : null) ?? 'Failed to load');
    }
    final data = body['data'];
    if (data is! Map) {
      return const ProgressReport(subjects: []);
    }
    return ProgressReport.fromJson(Map<String, dynamic>.from(data));
  } on DioException catch (e) {
    throw ErrorMapper.fromDio(e);
  }
});
