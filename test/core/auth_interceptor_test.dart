import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/network/auth_interceptor.dart';
import 'package:loay_mohamed_elearning/core/storage/secure_token_store.dart';
import 'package:mocktail/mocktail.dart';

class _MockTokenStore extends Mock implements SecureTokenStore {}

class _RequestHandler extends Mock implements RequestInterceptorHandler {}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(Options());
  });

  test('AuthInterceptor attaches Bearer token when present', () async {
    final store = _MockTokenStore();
    when(() => store.read()).thenAnswer((_) async => const TokenBundle(
          accessToken: 'abc',
          refreshToken: 'r',
        ));
    final interceptor = AuthInterceptor(
      tokenStore: store,
      refreshClient: Dio(),
      refreshPath: '/api/v1/auth/refresh',
      onForceLogout: () async {},
    );

    final req = RequestOptions(path: '/x');
    final handler = _RequestHandler();
    when(() => handler.next(any())).thenReturn(null);

    await interceptor.onRequest(req, handler);

    expect(req.headers['Authorization'], 'Bearer abc');
    verify(() => handler.next(req)).called(1);
  });

  test('AuthInterceptor skips Bearer when skipAuth set', () async {
    final store = _MockTokenStore();
    when(() => store.read()).thenAnswer((_) async => null);
    final interceptor = AuthInterceptor(
      tokenStore: store,
      refreshClient: Dio(),
      refreshPath: '/api/v1/auth/refresh',
      onForceLogout: () async {},
    );

    final req = RequestOptions(path: '/x', extra: {'skipAuth': true});
    final handler = _RequestHandler();
    when(() => handler.next(any())).thenReturn(null);

    await interceptor.onRequest(req, handler);

    expect(req.headers.containsKey('Authorization'), false);
  });
}
