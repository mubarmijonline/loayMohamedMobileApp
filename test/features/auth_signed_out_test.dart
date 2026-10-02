import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/providers.dart';
import 'package:loay_mohamed_elearning/core/storage/secure_token_store.dart';
import 'package:loay_mohamed_elearning/features/auth/presentation/auth_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _EmptyTokenStore implements SecureTokenStore {
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
  test('a request refused after signing out does not report an expired '
      'session', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final tokens = _EmptyTokenStore();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        tokenStoreProvider.overrideWithValue(tokens),
      ],
    );
    addTearDown(container.dispose);

    final auth = container.read(authControllerProvider.notifier);
    await auth.bootstrap(); // no tokens: signed out, no message
    expect(container.read(authControllerProvider).status,
        AuthStatus.unauthenticated);

    // What the interceptor does when a straggling request comes back 401.
    await auth.forceLogout(reason: 'token_expired');

    final state = container.read(authControllerProvider);
    expect(state.status, AuthStatus.unauthenticated);
    expect(state.error, isNull,
        reason: 'it used to say "Session expired. Please sign in again."');
    expect(tokens.clears, 1);
  });
}
