import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/error/error_mapper.dart';
import 'package:loay_mohamed_elearning/core/error/failures.dart';

DioException _err(int status, [Object? body]) {
  final req = RequestOptions(path: '/x');
  return DioException(
    requestOptions: req,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: req, statusCode: status, data: body),
  );
}

void main() {
  test('401 maps to UnauthorizedFailure', () {
    expect(ErrorMapper.fromDio(_err(401)), isA<UnauthorizedFailure>());
  });
  test('403 maps to ForbiddenFailure', () {
    expect(ErrorMapper.fromDio(_err(403)), isA<ForbiddenFailure>());
  });
  test('404 maps to NotFoundFailure', () {
    expect(ErrorMapper.fromDio(_err(404)), isA<NotFoundFailure>());
  });
  test('422 maps to ValidationFailure with envelope message', () {
    final f = ErrorMapper.fromDio(_err(422, {
      'success': false,
      'error': {'code': 'invalid_email', 'message': 'Email is invalid'},
    }));
    expect(f, isA<ValidationFailure>());
    expect(f.message, 'Email is invalid');
    expect(f.code, 'invalid_email');
  });
  test('5xx maps to ServerFailure', () {
    expect(ErrorMapper.fromDio(_err(503)), isA<ServerFailure>());
  });
  test('Connection error -> NetworkFailure', () {
    final req = RequestOptions(path: '/x');
    final e = DioException(requestOptions: req, type: DioExceptionType.connectionError);
    expect(ErrorMapper.fromDio(e), isA<NetworkFailure>());
  });
  test('Timeout -> TimeoutFailure', () {
    final req = RequestOptions(path: '/x');
    final e = DioException(requestOptions: req, type: DioExceptionType.receiveTimeout);
    expect(ErrorMapper.fromDio(e), isA<TimeoutFailure>());
  });
}
