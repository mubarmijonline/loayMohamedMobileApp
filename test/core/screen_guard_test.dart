import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/security/capture_event.dart';
import 'package:loay_mohamed_elearning/core/security/capture_event_queue.dart';
import 'package:loay_mohamed_elearning/core/security/screen_guard.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the native side so the channel contract can be asserted
/// without a device.
class _FakeNative {
  _FakeNative({this.protected = true, this.compromised = false});

  bool protected;
  bool compromised;
  final List<String> calls = [];

  Future<Object?> handle(MethodCall call) async {
    calls.add(call.method);
    return switch (call.method) {
      'enable' || 'disable' => null,
      'isProtected' => protected,
      'isCaptured' => false,
      'hasExternalDisplay' => false,
      'isDeviceCompromised' => compromised,
      _ => throw MissingPluginException(call.method),
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const method = MethodChannel('app/playback_security');
  const eventChannelName = 'app/playback_security/events';

  late _FakeNative native;
  late CaptureEventQueue queue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    queue = CaptureEventQueue(await SharedPreferences.getInstance());
    native = _FakeNative();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(method, native.handle);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(method, null);
  });

  /// Pushes an event through the platform event channel, the way native does.
  Future<void> emitNative(Map<String, Object?> payload) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      eventChannelName,
      const StandardMethodCodec().encodeSuccessEnvelope(payload),
      (_) {},
    );
  }

  group('protection state', () {
    test('enable() reports protected when the platform confirms it', () async {
      final guard = ScreenGuard(queue: queue);
      expect(await guard.enable(), isTrue);
      expect(guard.isProtected, isTrue);
      expect(native.calls, contains('enable'));
      expect(
        native.calls,
        contains('isProtected'),
        reason: 'must ask the platform, not assume enable() worked',
      );
      await guard.dispose();
    });

    test('enable() reports UNPROTECTED when the platform says so', () async {
      native.protected = false;
      final guard = ScreenGuard(queue: queue);

      expect(
        await guard.enable(),
        isFalse,
        reason: 'a silent failure here is the whole risk — the player must '
            'be able to refuse to render',
      );
      expect(guard.isProtected, isFalse);
      await guard.dispose();
    });

    test('an unprotected result is queued, not swallowed', () async {
      native.protected = false;
      final guard = ScreenGuard(queue: queue);
      await guard.enable();

      final queued = queue.read();
      expect(queued, isNotEmpty);
      expect(queued.last.type, CaptureEventType.protectionUnavailable);
      await guard.dispose();
    });

    test('no native implementation is treated as unprotected', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(method, null);
      final guard = ScreenGuard(queue: queue);

      // Failing open here would render video on a platform with no protection
      // at all.
      expect(await guard.enable(), isFalse);
      await guard.dispose();
    });
  });

  group('capture events', () {
    test('native events reach the stream keyed on `event`', () async {
      final guard = ScreenGuard(queue: queue);
      await guard.enable();

      final received = <CaptureEvent>[];
      final sub = guard.events.listen(received.add);

      // This is the exact payload shape MainActivity/AppDelegate send. An
      // earlier version keyed it `type`, and every event was silently
      // filtered out — the stream never delivered anything.
      await emitNative({'event': 'screenshot', 'platform': 'ios'});
      await pumpEventQueue();

      expect(received, hasLength(1));
      expect(received.single.type, CaptureEventType.screenshot);
      await sub.cancel();
      await guard.dispose();
    });

    test('events are tagged with the content being watched', () async {
      final guard = ScreenGuard(queue: queue);
      await guard.enable();
      guard.bindContent('content-42');

      await emitNative({'event': 'recording_detected'});
      await pumpEventQueue();

      expect(
        queue.read().last.contentId,
        'content-42',
        reason: 'a queued capture must be attributable to a lesson',
      );
      await guard.dispose();
    });

    test('recording blocks playback; ending it clears the block', () {
      expect(CaptureEventType.recordingStarted.blocksPlayback, isTrue);
      expect(CaptureEventType.externalDisplayConnected.blocksPlayback, isTrue);
      expect(CaptureEventType.protectionUnavailable.blocksPlayback, isTrue);
      expect(CaptureEventType.recordingStopped.clearsBlock, isTrue);
      // A screenshot is after the fact — there is nothing to block.
      expect(CaptureEventType.screenshot.blocksPlayback, isFalse);
    });

    test('an unrecognised native event is kept, not dropped', () async {
      final guard = ScreenGuard(queue: queue);
      await guard.enable();

      await emitNative({'event': 'some_new_native_signal'});
      await pumpEventQueue();

      final last = queue.read().last;
      expect(last.type, CaptureEventType.unknown);
      expect(
        last.raw,
        'some_new_native_signal',
        reason: 'a native change should show up in the queue rather than '
            'vanishing',
      );
      await guard.dispose();
    });
  });

  group('capture queue', () {
    test('survives a round trip through storage', () async {
      await queue.add(
        CaptureEvent(
          type: CaptureEventType.screenshot,
          at: DateTime.utc(2026, 9, 4, 12, 30),
          contentId: 'c1',
        ),
      );
      final back = queue.read().single;
      expect(back.type, CaptureEventType.screenshot);
      expect(back.contentId, 'c1');
      expect(back.at.toUtc(), DateTime.utc(2026, 9, 4, 12, 30));
    });

    test('counts repeat offences for escalation', () async {
      for (var i = 0; i < 3; i++) {
        await queue.add(
          CaptureEvent(
            type: CaptureEventType.screenshot,
            at: DateTime.now(),
          ),
        );
      }
      expect(queue.countOf(CaptureEventType.screenshot), 3);
      expect(queue.countOf(CaptureEventType.recordingStarted), 0);
    });

    test('is bounded so a recording loop cannot grow it forever', () async {
      for (var i = 0; i < CaptureEventQueue.maxEvents + 25; i++) {
        await queue.add(
          CaptureEvent(
            type: CaptureEventType.screenshot,
            at: DateTime.now(),
            meta: {'i': i},
          ),
        );
      }
      final all = queue.read();
      expect(all, hasLength(CaptureEventQueue.maxEvents));
      // The newest window is kept.
      expect(all.last.meta['i'], CaptureEventQueue.maxEvents + 24);
    });
  });
}
