import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../../core/error/failures.dart';

/// Returned by either Apple or Google sign-in. The repository sends this
/// to `POST /auth/social`.
class SocialCredential {
  const SocialCredential({
    required this.provider,
    required this.idToken,
    this.authorizationCode,
    this.email,
    this.name,
    this.nonce,
  });
  final String provider; // 'apple' | 'google'
  final String idToken;
  final String? authorizationCode;
  final String? email;
  final String? name;
  final String? nonce;
}

class SocialAuthService {
  SocialAuthService({GoogleSignIn? google})
      : _google = google ??
            GoogleSignIn(
              scopes: const ['email', 'profile', 'openid'],
            );

  final GoogleSignIn _google;

  // ─── Apple ─────────────────────────────────────────────────────────────
  Future<SocialCredential> signInWithApple() async {
    if (!await SignInWithApple.isAvailable()) {
      throw const ValidationFailure(
        'Sign in with Apple is not available on this device.',
      );
    }
    final raw = _randomNonce();
    final hashed = sha256.convert(utf8.encode(raw)).toString();
    try {
      final res = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashed,
      );
      final idToken = res.identityToken;
      if (idToken == null || idToken.isEmpty) {
        throw const ServerFailure('Apple did not return an identity token.');
      }
      final fullName = [res.givenName, res.familyName]
          .whereType<String>()
          .where((p) => p.trim().isNotEmpty)
          .join(' ')
          .trim();
      return SocialCredential(
        provider: 'apple',
        idToken: idToken,
        authorizationCode: res.authorizationCode,
        email: res.email,
        name: fullName.isEmpty ? null : fullName,
        nonce: raw,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const ValidationFailure('Sign-in was cancelled.');
      }
      throw ServerFailure(e.message);
    } catch (e) {
      throw ServerFailure(e.toString());
    }
  }

  // ─── Google ────────────────────────────────────────────────────────────
  Future<SocialCredential> signInWithGoogle() async {
    try {
      // Cold-start the SDK so re-tries don't return a stale account.
      await _google.signOut().catchError((_) => null);
      final account = await _google.signIn();
      if (account == null) {
        throw const ValidationFailure('Sign-in was cancelled.');
      }
      final auth = await account.authentication;
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw const ServerFailure(
          'Google did not return an ID token. '
          'Did you set the iOS OAuth client ID in Info.plist?',
        );
      }
      return SocialCredential(
        provider: 'google',
        idToken: idToken,
        authorizationCode: auth.accessToken,
        email: account.email,
        name: account.displayName,
      );
    } on PlatformException catch (e) {
      throw ServerFailure(e.message ?? e.code);
    } catch (e) {
      if (e is AppFailure) rethrow;
      throw ServerFailure(e.toString());
    }
  }

  Future<void> signOutAll() async {
    await _google.signOut().catchError((_) => null);
  }

  static String _randomNonce([int length = 32]) {
    const chars =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final r = Random.secure();
    return List.generate(length, (_) => chars[r.nextInt(chars.length)]).join();
  }
}
