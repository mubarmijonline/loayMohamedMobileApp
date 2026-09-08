import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'screen_guard.dart';

/// Why playback is being refused, if it is.
enum PlaybackDenial {
  /// Platform capture protection could not be confirmed active. Rendering
  /// video now would show it under a protection that silently failed.
  unprotected,

  /// Rooted / jailbroken device — every client-side protection here is
  /// defeatable, so video specifically is withheld.
  compromisedDevice,
}

class PlaybackPermission extends Equatable {
  const PlaybackPermission.allowed() : denial = null;
  const PlaybackPermission.denied(PlaybackDenial reason) : denial = reason;

  final PlaybackDenial? denial;

  bool get isAllowed => denial == null;

  /// User-facing copy. Deliberately says what is wrong and what to do, without
  /// implying the student did something wrong when they merely have a rooted
  /// phone.
  String get title => switch (denial) {
        PlaybackDenial.compromisedDevice =>
          'Video is unavailable on this device',
        PlaybackDenial.unprotected => 'Video cannot be played securely',
        null => '',
      };

  String get message => switch (denial) {
        PlaybackDenial.compromisedDevice =>
          'Lesson videos cannot be played on rooted or jailbroken devices. '
              'Everything else in the app still works — you can view '
              'assignments, submit work and check your marks.',
        PlaybackDenial.unprotected =>
          'Screen protection could not be enabled, so lesson videos are not '
              'available right now. Please restart the app, and contact '
              'support if this keeps happening.',
        null => '',
      };

  @override
  List<Object?> get props => [denial];
}

/// Resolves whether this device may play video, right now.
///
/// This is the integration check the security design turns on: rather than
/// assuming `ScreenGuard.enable()` worked, it asks the platform whether
/// protection is genuinely in force, and refuses to render a player if the
/// answer is anything other than yes.
///
/// Silent failure here is the whole risk. An app that believes it is protected
/// and is not is worse than one that never tried.
final playbackPermissionProvider =
    FutureProvider<PlaybackPermission>((ref) async {
  final integrity = ref.read(deviceIntegrityProvider);
  if (await integrity.isCompromised()) {
    return const PlaybackPermission.denied(PlaybackDenial.compromisedDevice);
  }

  final guard = ref.read(screenGuardProvider);
  final protected = await guard.enable();
  if (!protected) {
    return const PlaybackPermission.denied(PlaybackDenial.unprotected);
  }

  return const PlaybackPermission.allowed();
});

/// Convenience for widgets that only need the guard once permission is known.
extension ScreenGuardRef on WidgetRef {
  ScreenGuard get screenGuard => read(screenGuardProvider);
}
