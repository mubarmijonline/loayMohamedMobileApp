import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/env/app_env.dart';
import 'package:loay_mohamed_elearning/core/error/failures.dart';
import 'package:loay_mohamed_elearning/core/network/api_client.dart';
import 'package:loay_mohamed_elearning/core/storage/secure_token_store.dart';
import 'package:loay_mohamed_elearning/features/auth/data/auth_repository.dart';

/// Account deletion against docs/mobile/BACKEND_ACCOUNT_DELETION.md. The route
/// is not deployed yet, so these pin the client half: what it sends, and that
/// a refusal leaves the student signed in.
class _Reply {
  const _Reply(this.status, this.body);
  final int status;
  final String body;
}

/// Like the adapter in submission_flow_test, but able to answer non-200 —
/// the refusal paths are the ones that matter here.
class _Adapter implements HttpClientAdapter {
  _Adapter(this.reply);
  _Reply reply;
  final List<RequestOptions> requests = [];
  final List<Map<String, dynamic>> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final raw = stream == null
        ? ''
        : utf8.decode((await stream.toList()).expand((c) => c).toList());
    bodies.add(raw.isEmpty ? {} : jsonDecode(raw) as Map<String, dynamic>);
    return ResponseBody.fromString(
      reply.body,
      reply.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _SpyTokenStore implements SecureTokenStore {
  int clears = 0;
  @override
  Future<void> clear() async => clears++;
  @override
  bool get isEphemeral => false;
  @override
  Future<TokenBundle?> read() async => null;
  @override
  Future<void> save(TokenBundle b) async {}
}

void main() {
  // AppEnv reads the bundled .env asset, so the binding must be up first.
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Adapter adapter;
  late _SpyTokenStore tokens;
  late AuthRepository repo;

  setUpAll(() async {
    await AppEnv.load(Flavor.dev);
  });

  setUp(() {
    tokens = _SpyTokenStore();
    final client = ApiClient(
      tokenStore: tokens,
      onForceLogout: ({String? reason, String? message}) async {},
    );
    adapter = _Adapter(
      const _Reply(200, '{"success":true,"data":{"deleted":true}}'),
    );
    client.dio.httpClientAdapter = adapter;
    repo = AuthRepository(client, tokens);
  });

  test('posts the password to /auth/account/delete', () async {
    await repo.deleteAccount(password: 'pw');
    final r = adapter.requests.single;
    expect(r.method, 'POST');
    expect(r.path, endsWith('/auth/account/delete'));
    expect(adapter.bodies.single, {'password': 'pw'});
  });

  test('a passwordless account sends the confirm phrase and no password',
      () async {
    await repo.deleteAccount(confirmPhrase: 'DELETE');
    expect(adapter.bodies.single, {'confirm': 'DELETE'});
  });

  test('clears tokens once the server confirms', () async {
    await repo.deleteAccount(password: 'pw');
    expect(tokens.clears, 1);
  });

  test('a wrong password throws the server code and keeps the session',
      () async {
    adapter.reply = const _Reply(
      400,
      '{"success":false,"error":{"code":"invalid_current_password",'
      '"message":"Current password is incorrect."}}',
    );
    await expectLater(
      repo.deleteAccount(password: 'wrong'),
      throwsA(
        isA<ValidationFailure>()
            .having((e) => e.code, 'code', 'invalid_current_password'),
      ),
    );
    expect(
      tokens.clears,
      0,
      reason: 'a mistyped password must not sign the student out',
    );
  });

  test('the undeployed route surfaces as NotFoundFailure', () async {
    // What the server answers today: the bare Flask 404, not the envelope.
    // The sheet maps this to "not available yet" rather than "Not found".
    adapter.reply = const _Reply(404, '{"error":"Not found"}');
    await expectLater(
      repo.deleteAccount(password: 'pw'),
      throwsA(isA<NotFoundFailure>()),
    );
    expect(tokens.clears, 0);
  });
}
