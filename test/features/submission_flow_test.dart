import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/env/app_env.dart';
import 'package:loay_mohamed_elearning/core/error/failures.dart';
import 'package:loay_mohamed_elearning/core/network/api_client.dart';
import 'package:loay_mohamed_elearning/core/storage/secure_token_store.dart';
import 'package:loay_mohamed_elearning/features/student_repository.dart';

/// Captures every outgoing request and replies from [_replies], so the
/// repository's wire format can be asserted without a network.
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this._replies);
  final String Function(RequestOptions o) _replies;

  final List<RequestOptions> requests = [];
  final List<String> bodies = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? stream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (stream != null) {
      final chunks = await stream.toList();
      bodies.add(
        utf8.decode(
          chunks.expand((c) => c).toList(),
          allowMalformed: true,
        ),
      );
    } else {
      bodies.add('');
    }
    return ResponseBody.fromString(
      _replies(options),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _NoopTokenStore implements SecureTokenStore {
  @override
  Future<void> clear() async {}
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

  late _CapturingAdapter adapter;
  late StudentRepository repo;

  setUpAll(() async {
    await AppEnv.load(Flavor.dev);
  });

  setUp(() {
    final client = ApiClient(
      tokenStore: _NoopTokenStore(),
      onForceLogout: ({String? reason, String? message}) async {},
    );
    adapter = _CapturingAdapter((o) {
      if (o.path.contains('/submit')) {
        return '{"success":true,"data":{"created":true}}';
      }
      // The re-read after submitting.
      return '{"success":true,"data":{"assignment":{"_id":"a1",'
          '"title":"HW","type":"homework"},"submission":{"_id":"s1",'
          '"assignment_id":"a1","status":"submitted","released":false}}}';
    });
    client.dio.httpClientAdapter = adapter;
    repo = StudentRepository(client);
  });

  group('submitAssignment (API_BRIEF §7)', () {
    test('rejects an empty submission before hitting the network', () async {
      await expectLater(
        repo.submitAssignment(id: 'a1'),
        throwsA(
          isA<ValidationFailure>()
              .having((e) => e.code, 'code', 'empty_submission'),
        ),
      );
      expect(
        adapter.requests,
        isEmpty,
        reason: 'the server would answer 400 empty_submission — do not '
            'spend a round trip discovering that',
      );
    });

    test('sends text as multipart and re-reads the assignment', () async {
      final a = await repo.submitAssignment(id: 'a1', textContent: 'my answer');

      expect(adapter.requests.first.path, contains('/assignments/a1/submit'));
      expect(adapter.requests.first.method, 'POST');
      expect(
        adapter.requests.first.contentType,
        contains('multipart/form-data'),
        reason: 'multipart is the only encoding that accepts files',
      );
      expect(adapter.bodies.first, contains('my answer'));

      // The submit route replies `{created: true}`, not an assignment, so a
      // second GET must fetch the real state.
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests[1].method, 'GET');
      expect(a.id, 'a1');
      expect(a.submission, isNotNull);
    });

    test('encodes answers as a JSON string', () async {
      await repo.submitAssignment(id: 'a1', answers: {'q1': 'B', 'q2': 'D'});
      final body = adapter.bodies.first;
      expect(body, contains('name="answers"'));
      // The server parses this field with json.loads — it must be a string,
      // not nested form fields, or it returns 400 invalid_answers.
      expect(body, contains('{"q1":"B","q2":"D"}'));
    });

    test('sends several files under attachments[]', () async {
      await repo.submitAssignment(
        id: 'a1',
        attachments: [
          MultipartFile.fromString('one', filename: 'p1.txt'),
          MultipartFile.fromString('two', filename: 'p2.txt'),
        ],
      );
      final body = adapter.bodies.first;
      expect(
        'attachments[]'.allMatches(body).length,
        2,
        reason: 'the route accepts multiple files; the first is mirrored '
            'into the legacy file_path/file_name fields',
      );
      expect(body, contains('p1.txt'));
      expect(body, contains('p2.txt'));
    });
  });

  group('notifications (API_BRIEF §13.4)', () {
    test('markNotificationRead refuses an empty id', () async {
      // POST /notifications/mark-read with no id silently marks EVERYTHING
      // read. That must be impossible to trigger by accident.
      await expectLater(
        repo.markNotificationRead(''),
        throwsA(isA<ArgumentError>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('markAllNotificationsRead uses the dedicated route', () async {
      await repo.markAllNotificationsRead();
      expect(
        adapter.requests.single.path,
        endsWith('/notifications/mark-all-read'),
      );
    });
  });
}
