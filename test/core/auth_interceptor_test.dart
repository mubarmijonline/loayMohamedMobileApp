import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/network/auth_interceptor.dart';
import 'package:loay_mohamed_elearning/core/storage/secure_token_store.dart';
import 'package:mocktail/mocktail.dart';

class _MockTokenStore extends Mock implements SecureTokenStore {}

class _RequestHandler extends Mock implements RequestInterceptorHandler {}

/// A token store backed by a plain field, so a refresh that saves a rotated
/// bundle is visible to the next read — mirrors the real store's behaviour.
class _FakeTokenStore implements SecureTokenStore {
  _FakeTokenStore(this._bundle);
  TokenBundle? _bundle;
  int saves = 0;

  @override
  bool get isEphemeral => false;

  @override
  Future<TokenBundle?> read() async => _bundle;

  @override
  Future<void> save(TokenBundle b) async {
    saves++;
    _bundle = b;
  }

  @override
  Future<void> clear() async => _bundle = null;
}

TokenBundle _bundle({
  String access = 'access-1',
  String refresh = 'refresh-1',
  Duration? age,
  Duration life = const Duration(hours: 1),
}) {
  final issued = DateTime.now().subtract(age ?? Duration.zero);
  return TokenBundle(
    accessToken: access,
    refreshToken: refresh,
    issuedAt: issued,
    expiresAt: issued.add(life),
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(RequestOptions(path: ''));
    registerFallbackValue(Options());
  });

  test('attaches Bearer token when present', () async {
    final store = _MockTokenStore();
    when(() => store.read()).thenAnswer((_) async => _bundle(access: 'abc'));
    final interceptor = AuthInterceptor(
      tokenStore: store,
      refreshClient: Dio(),
      refreshPath: '/api/v1/auth/refresh',
      onForceLogout: ({String? reason, String? message}) async {},
    );

    final req = RequestOptions(path: '/x');
    final handler = _RequestHandler();
    when(() => handler.next(any())).thenReturn(null);

    await interceptor.onRequest(req, handler);

    expect(req.headers['Authorization'], 'Bearer abc');
    verify(() => handler.next(req)).called(1);
  });

  test('skips Bearer when skipAuth is set', () async {
    final store = _MockTokenStore();
    when(() => store.read()).thenAnswer((_) async => null);
    final interceptor = AuthInterceptor(
      tokenStore: store,
      refreshClient: Dio(),
      refreshPath: '/api/v1/auth/refresh',
      onForceLogout: ({String? reason, String? message}) async {},
    );

    final req = RequestOptions(path: '/x', extra: {'skipAuth': true});
    final handler = _RequestHandler();
    when(() => handler.next(any())).thenReturn(null);

    await interceptor.onRequest(req, handler);

    expect(req.headers.containsKey('Authorization'), false);
  });

  group('token expiry tracking (API_BRIEF §2)', () {
    test('refreshes proactively past 80% of the access token life', () {
      // 55 minutes into a 60 minute life = 91%, past the threshold.
      expect(
        _bundle(age: const Duration(minutes: 55)).shouldRefreshProactively,
        isTrue,
      );
      // 30 minutes in = 50%, well short of it.
      expect(
        _bundle(age: const Duration(minutes: 30)).shouldRefreshProactively,
        isFalse,
      );
    });

    test('honours a shortened server-side TTL', () {
      // Server dropped MOBILE_ACCESS_TOKEN_TTL_SECONDS to 10 minutes; 9
      // minutes in is 90% and must trigger.
      final short = _bundle(
        age: const Duration(minutes: 9),
        life: const Duration(minutes: 10),
      );
      expect(short.shouldRefreshProactively, isTrue);
    });

    test('isRefreshExpired is false when the server sent no refresh TTL', () {
      expect(_bundle().isRefreshExpired, isFalse);
    });

    test('fromAuthPayload stores both TTLs and rotates the refresh token', () {
      final b = TokenBundle.fromAuthPayload({
        'access_token': 'a2',
        'refresh_token': 'r2',
        'expires_in': 3600,
        'refresh_expires_in': 2592000,
      });
      expect(b, isNotNull);
      expect(b!.accessToken, 'a2');
      expect(b.refreshToken, 'r2');
      expect(b.expiresAt!.difference(b.issuedAt!).inSeconds, closeTo(3600, 2));
      expect(b.refreshExpiresAt!.difference(b.issuedAt!).inDays, 30);
    });

    test('fromAuthPayload keeps the old refresh token when none is returned',
        () {
      final b = TokenBundle.fromAuthPayload(
        {'access_token': 'a3', 'expires_in': 3600},
        fallbackRefresh: 'kept',
      );
      expect(b!.refreshToken, 'kept');
    });

    test('fromAuthPayload returns null without an access token', () {
      expect(TokenBundle.fromAuthPayload({'refresh_token': 'r'}), isNull);
    });
  });

  group('single-flight refresh (API_BRIEF §2)', () {
    test('concurrent 401s trigger exactly one refresh call', () async {
      final store = _FakeTokenStore(_bundle());
      var refreshCalls = 0;

      final refreshDio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      refreshDio.httpClientAdapter = _StubAdapter((options) {
        if (options.path.contains('/auth/refresh')) {
          refreshCalls++;
          return ResponseBody.fromString(
            '{"success":true,"data":{"access_token":"access-2",'
            '"refresh_token":"refresh-2","expires_in":3600,'
            '"refresh_expires_in":2592000}}',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        // The replayed original request.
        return ResponseBody.fromString(
          '{"success":true,"data":{"ok":true}}',
          200,
          headers: {
            Headers.contentTypeHeader: [Headers.jsonContentType],
          },
        );
      });

      final interceptor = AuthInterceptor(
        tokenStore: store,
        refreshClient: refreshDio,
        refreshPath: '/api/v1/auth/refresh',
        onForceLogout: ({String? reason, String? message}) async {},
      );

      // Fire several 401s at once — they must queue behind one refresh.
      await Future.wait(
        List.generate(5, (i) async {
          final req = RequestOptions(path: '/student/dashboard$i');
          final err = DioException(
            requestOptions: req,
            response: Response<dynamic>(
              requestOptions: req,
              statusCode: 401,
              data: {
                'success': false,
                'error': {'code': 'token_expired', 'message': 'expired'},
              },
            ),
          );
          final completer = _ErrorHandlerSpy();
          await interceptor.onError(err, completer);
        }),
      );

      expect(
        refreshCalls,
        1,
        reason: 'parallel refreshes rotate each other out and log the user '
            'out; every 401 must await the same in-flight call',
      );
      expect(store.saves, 1);
      expect(
        (await store.read())!.refreshToken,
        'refresh-2',
        reason: 'the rotated refresh token must be persisted',
      );
    });

    test('session_revoked is terminal and never refreshes', () async {
      final store = _FakeTokenStore(_bundle());
      var refreshCalls = 0;
      String? loggedOutReason;

      final refreshDio = Dio();
      refreshDio.httpClientAdapter = _StubAdapter((_) {
        refreshCalls++;
        return ResponseBody.fromString('{}', 200);
      });

      final interceptor = AuthInterceptor(
        tokenStore: store,
        refreshClient: refreshDio,
        refreshPath: '/api/v1/auth/refresh',
        onForceLogout: ({String? reason, String? message}) async {
          loggedOutReason = reason;
        },
      );

      final req = RequestOptions(path: '/student/dashboard');
      await interceptor.onError(
        DioException(
          requestOptions: req,
          response: Response<dynamic>(
            requestOptions: req,
            statusCode: 401,
            data: {
              'success': false,
              'error': {'code': 'session_revoked', 'message': 'revoked'},
            },
          ),
        ),
        _ErrorHandlerSpy(),
      );

      expect(loggedOutReason, 'session_revoked');
      expect(
        refreshCalls,
        0,
        reason: 'refresh cannot help a revoked session — §13.3 notes it '
            'even succeeds, minting a token that is rejected on use',
      );
    });
  });
}

/// Minimal handler stub — records what the interceptor decided.
class _ErrorHandlerSpy extends ErrorInterceptorHandler {
  bool resolved = false;
  bool rejected = false;

  @override
  void resolve(Response<dynamic> response) => resolved = true;

  @override
  void next(DioException err) => rejected = true;

  @override
  void reject(DioException error) => rejected = true;
}

/// Routes every request to [_respond] without touching the network.
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this._respond);
  final ResponseBody Function(RequestOptions options) _respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? stream,
    Future<void>? cancelFuture,
  ) async =>
      _respond(options);

  @override
  void close({bool force = false}) {}
}
