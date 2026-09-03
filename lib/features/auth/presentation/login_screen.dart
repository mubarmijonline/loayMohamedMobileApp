import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/utils/countries.dart';
import '../../../core/utils/country_phone_field.dart';
import 'auth_controller.dart';
import 'parent_otp_screen.dart';
import 'social_auth_buttons.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _LoginMode { phone, email }
enum _RoleTab { student, parent }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  Country _country = kDefaultCountry;
  _LoginMode _mode = _LoginMode.phone;
  _RoleTab _role = _RoleTab.student;
  bool _obscure = true;
  bool _remember = true;

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;

    if (_role == _RoleTab.parent) {
      final phone = toE164(_country.code, _phone.text);
      final res = await ref
          .read(authControllerProvider.notifier)
          .requestParentOtp(phone: phone);
      if (!mounted || res == null) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ParentOtpScreen(
            phone: phone,
            expiresIn: res.expiresIn,
            resendAfter: res.resendAfter,
          ),
        ),
      );
      return;
    }

    final identifier = _mode == _LoginMode.phone
        ? toE164(_country.code, _phone.text)
        : _email.text.trim();
    final ok = await ref.read(authControllerProvider.notifier).login(
          identifier: identifier,
          password: _password.text,
          rememberMe: _remember,
        );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    return Scaffold(
      // Tap anywhere outside a text field to dismiss the keyboard. This is the
      // most reliable way to dismiss the numeric keyboard on iOS where there is
      // no native "Done" key for number inputs.
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            Container(
              height: 320,
              decoration: const BoxDecoration(
                  gradient: AppColors.authBackgroundGradient,),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: AppSpacing.lg),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.school_rounded,
                                color: Colors.white,
                                size: 48,),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome back',
                                style: theme.textTheme.headlineSmall
                                    ?.copyWith(color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _role == _RoleTab.parent
                                    ? 'Parent portal'
                                    : 'Sign in to continue learning',
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg,),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(AppRadius.xl),
                          topRight: Radius.circular(AppRadius.xl),
                        ),
                      ),
                      child: Form(
                        key: _form,
                        child: ListView(
                          children: [
                            // ── Role toggle: Student / Parent ──────────
                            _RoleToggle(
                              role: _role,
                              onChanged: (r) => setState(() => _role = r),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            // Social buttons + phone/email toggle only for students
                            if (_role == _RoleTab.student) ...[
                              const SocialAuthButtons(),
                              const SizedBox(height: AppSpacing.lg),
                              _ModeToggle(
                                mode: _mode,
                                onChanged: (m) => setState(() => _mode = m),
                              ),
                              const SizedBox(height: AppSpacing.lg),
                            ],
                            // Phone field
                            if (_role == _RoleTab.parent ||
                                _mode == _LoginMode.phone)
                              CountryPhoneField(
                                country: _country,
                                controller: _phone,
                                onCountryChanged: (c) =>
                                    setState(() => _country = c),
                                label: 'Mobile number',
                                textInputAction: TextInputAction.next,
                              )
                            else
                              TextFormField(
                                controller: _email,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'Email',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: (v) {
                                  final s = v?.trim() ?? '';
                                  if (s.isEmpty) return 'Email is required';
                                  if (!RegExp(r'^[\w.+-]+@[\w-]+\.[\w.-]+$')
                                      .hasMatch(s)) {
                                    return 'Enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                            if (_role == _RoleTab.student) ...[
                              const SizedBox(height: AppSpacing.md),
                              TextFormField(
                                controller: _password,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'Password',
                                  prefixIcon: const Icon(Icons.lock_outline),
                                  suffixIcon: IconButton(
                                    icon: Icon(_obscure
                                        ? Icons.visibility
                                        : Icons.visibility_off,),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) => (v ?? '').length < 6
                                    ? 'Enter your password'
                                    : null,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Checkbox(
                                    value: _remember,
                                    onChanged: (v) =>
                                        setState(() => _remember = v ?? true),
                                  ),
                                  const Text('Remember me'),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: AppSpacing.md),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.primarySurface,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.info_outline_rounded,
                                        size: 18, color: AppColors.primary),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'We will send a verification code to this number if it is linked to a student.',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: AppSpacing.md),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: state.loading ? null : _submit,
                                icon: Icon(_role == _RoleTab.parent
                                    ? Icons.sms_outlined
                                    : Icons.login_rounded),
                                label: state.loading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.4,),
                                      )
                                    : Text(_role == _RoleTab.parent
                                        ? 'Send Verification Code'
                                        : 'Sign in'),
                              ),
                            ),
                            if (state.error != null) ...[
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                state.error!.message,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error,),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: AppSpacing.lg),
                            if (_role == _RoleTab.student)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text("Don't have an account?"),
                                  TextButton(
                                    onPressed: () => Navigator.of(context)
                                        .pushNamed('/register'),
                                    child: const Text('Create one'),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.10),
                  ),
                ],
              ),
            ),
            // Floating "Done" pill above the keyboard. Visible only while the
            // keyboard is open. Lets the user dismiss the iOS dial-pad which
            // otherwise has no return key.
            if (MediaQuery.of(context).viewInsets.bottom > 0)
              Positioned(
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                child: Material(
                  color: AppColors.primary,
                  shape: const StadiumBorder(),
                  elevation: 6,
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: 18, vertical: 10,),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.keyboard_hide_rounded,
                              color: Colors.white, size: 18,),
                          SizedBox(width: 6),
                          Text(
                            'Done',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});
  final _LoginMode mode;
  final ValueChanged<_LoginMode> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, IconData icon, _LoginMode value) {
      final selected = mode == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? Colors.white : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: selected
                        ? AppColors.primary
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppColors.primary
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.primarySurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          tab('Mobile', Icons.phone_android_rounded, _LoginMode.phone),
          tab('Email', Icons.email_outlined, _LoginMode.email),
        ],
      ),
    );
  }
}

/// Top-level Student / Parent tab switcher.
class _RoleToggle extends StatelessWidget {
  const _RoleToggle({required this.role, required this.onChanged});
  final _RoleTab role;
  final ValueChanged<_RoleTab> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, IconData icon, _RoleTab value) {
      final selected = role == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.symmetric(vertical: 13),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ]
                  : null,
            ),
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 18,
                    color: selected
                        ? Colors.white
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65)),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? Colors.white
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          tab('Student', Icons.school_rounded, _RoleTab.student),
          tab('Parent', Icons.family_restroom_rounded, _RoleTab.parent),
        ],
      ),
    );
  }
}
