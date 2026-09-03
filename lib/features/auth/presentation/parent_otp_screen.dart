import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_spacing.dart';
import 'auth_controller.dart';

/// Step 2 of parent passwordless login.
///
/// Pushed from [LoginScreen] after `requestParentOtp` succeeds. Shows a
/// 6-digit code field plus a resend countdown. On verify, the controller
/// authenticates and routes to `/parent/home`.
class ParentOtpScreen extends ConsumerStatefulWidget {
  const ParentOtpScreen({
    super.key,
    required this.phone,
    required this.expiresIn,
    required this.resendAfter,
  });

  /// E.164 phone the user just entered on the login screen.
  final String phone;

  /// Lifetime of this code in seconds (from backend).
  final int expiresIn;

  /// Seconds before the user may request a new code (from backend).
  final int resendAfter;

  @override
  ConsumerState<ParentOtpScreen> createState() => _ParentOtpScreenState();
}

class _ParentOtpScreenState extends ConsumerState<ParentOtpScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  Timer? _ticker;
  int _resendIn = 0;
  int _expiresIn = 0;

  @override
  void initState() {
    super.initState();
    _resendIn = widget.resendAfter;
    _expiresIn = widget.expiresIn;
    _startTicker();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_resendIn > 0) _resendIn--;
        if (_expiresIn > 0) _expiresIn--;
      });
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    final code = _code.text.trim();
    if (code.length != 6) return;
    final ok = await ref.read(authControllerProvider.notifier).verifyParentOtp(
          phone: widget.phone,
          code: code,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/parent/home', (_) => false);
    }
  }

  Future<void> _resend() async {
    final res = await ref
        .read(authControllerProvider.notifier)
        .requestParentOtp(phone: widget.phone);
    if (!mounted || res == null) return;
    setState(() {
      _resendIn = res.resendAfter;
      _expiresIn = res.expiresIn;
      _code.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Verification code sent')),
    );
  }

  String _fmt(int s) {
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final r = (s % 60).toString().padLeft(2, '0');
    return '$m:$r';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(authControllerProvider);
    final canResend = _resendIn == 0;
    final expired = _expiresIn == 0;

    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusScope.of(context).unfocus(),
          child: Stack(
            children: [
              Container(
                height: 280,
                decoration: const BoxDecoration(
                  gradient: AppColors.authBackgroundGradient,
                ),
              ),
              SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            color: Colors.white),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg),
                      child: Text(
                        'Verify it\'s you',
                        style: theme.textTheme.headlineSmall
                            ?.copyWith(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg),
                      child: Text(
                        'We sent a 6-digit code to ${widget.phone}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          AppSpacing.xl,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(AppRadius.xl),
                            topRight: Radius.circular(AppRadius.xl),
                          ),
                        ),
                        child: ListView(
                          children: [
                            TextField(
                              controller: _code,
                              focusNode: _focus,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 28,
                                letterSpacing: 12,
                                fontWeight: FontWeight.w700,
                              ),
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                counterText: '',
                                hintText: '••••••',
                                hintStyle: TextStyle(
                                  letterSpacing: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              onChanged: (v) {
                                if (v.length == 6 && !state.loading) {
                                  _verify();
                                }
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  expired
                                      ? Icons.error_outline_rounded
                                      : Icons.schedule_rounded,
                                  size: 16,
                                  color: expired
                                      ? theme.colorScheme.error
                                      : theme.colorScheme.onSurface
                                          .withValues(alpha: 0.6),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  expired
                                      ? 'Code expired — request a new one'
                                      : 'Code expires in ${_fmt(_expiresIn)}',
                                  style: TextStyle(
                                    color: expired
                                        ? theme.colorScheme.error
                                        : theme.colorScheme.onSurface
                                            .withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: state.loading ? null : _verify,
                                icon: const Icon(Icons.verified_rounded),
                                label: state.loading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.4),
                                      )
                                    : const Text('Verify & Continue'),
                              ),
                            ),
                            if (state.error != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                state.error!.message,
                                style: TextStyle(
                                    color: theme.colorScheme.error),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Text("Didn't get the code?"),
                                TextButton(
                                  onPressed:
                                      (canResend && !state.loading) ? _resend : null,
                                  child: Text(
                                    canResend
                                        ? 'Resend'
                                        : 'Resend in ${_fmt(_resendIn)}',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
