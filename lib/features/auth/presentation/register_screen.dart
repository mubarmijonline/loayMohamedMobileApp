import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/app_colors.dart';
import '../../../core/design/app_spacing.dart';
import '../../../core/utils/countries.dart';
import '../../../core/utils/country_phone_field.dart';
import 'auth_controller.dart';
import 'social_auth_buttons.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _parentPhone = TextEditingController();
  final _school = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  Country _country = kDefaultCountry;
  Country _parentCountry = kDefaultCountry;
  int _grade = 9;
  bool _obscure = true;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _parentPhone.dispose();
    _school.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;
    final ok = await ref.read(authControllerProvider.notifier).createStudentUser(
          name: _name.text.trim(),
          email: _email.text.trim(),
          phone: normalizePhoneDigits(_phone.text),
          countryCode: _country.code,
          parentPhone: normalizePhoneDigits(_parentPhone.text),
          parentCountryCode: _parentCountry.code,
          school: _school.text.trim(),
          grade: _grade,
          password: _password.text,
          rememberMe: true,
        );
    if (!mounted) return;
    if (ok) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            Container(
              height: 280,
              decoration:
                  const BoxDecoration(gradient: AppColors.authBackgroundGradient),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded,
                        color: Colors.white,),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 52,
                          height: 52,
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.school_rounded,
                                color: Colors.white,
                                size: 36,),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'Create your account',
                            style: theme.textTheme.headlineSmall
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,),
                    child: Text(
                      'Add your student details to get started.',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.lg,),
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
                            const SocialAuthButtons(
                              dividerLabel: 'or sign up with email',
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            TextFormField(
                              controller: _name,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'Full name',
                                prefixIcon:
                                    Icon(Icons.person_outline_rounded),
                              ),
                              validator: (v) =>
                                  (v?.trim().length ?? 0) < 2
                                      ? 'Name must be at least 2 characters'
                                      : null,
                            ),
                            const SizedBox(height: AppSpacing.md),
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
                            const SizedBox(height: AppSpacing.md),
                            CountryPhoneField(
                              country: _country,
                              controller: _phone,
                              onCountryChanged: (c) =>
                                  setState(() => _country = c),
                              label: 'Student mobile number',
                              icon: Icons.phone_android_rounded,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            CountryPhoneField(
                              country: _parentCountry,
                              controller: _parentPhone,
                              onCountryChanged: (c) =>
                                  setState(() => _parentCountry = c),
                              label: 'Parent mobile number',
                              icon: Icons.family_restroom_rounded,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _school,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                labelText: 'School',
                                prefixIcon: Icon(Icons.school_outlined),
                              ),
                              validator: (v) =>
                                  (v?.trim().isNotEmpty ?? false)
                                      ? null
                                      : 'School is required',
                            ),
                            const SizedBox(height: AppSpacing.md),
                            DropdownButtonFormField<int>(
                              value: _grade,
                              decoration: const InputDecoration(
                                labelText: 'Grade',
                                prefixIcon: Icon(Icons.class_rounded),
                              ),
                              items: const [9, 10, 11, 12]
                                  .map((g) => DropdownMenuItem<int>(
                                        value: g,
                                        child: Text('Grade $g'),
                                      ),)
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) setState(() => _grade = v);
                              },
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _password,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.next,
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
                              validator: (v) => (v ?? '').length < 8
                                  ? 'Password must be at least 8 characters'
                                  : null,
                            ),
                            const SizedBox(height: AppSpacing.md),
                            TextFormField(
                              controller: _confirm,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: 'Confirm password',
                                prefixIcon: Icon(Icons.lock_reset_rounded),
                              ),
                              validator: (v) => v == _password.text
                                  ? null
                                  : 'Passwords do not match',
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: state.loading ? null : _submit,
                                icon: const Icon(
                                    Icons.person_add_alt_1_rounded,),
                                label: state.loading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.4,),
                                      )
                                    : const Text('Create Account'),
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
                          ],
                        ),
                      ),
                    )
                        .animate()
                        .fadeIn(duration: 400.ms)
                        .slideY(begin: 0.12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
