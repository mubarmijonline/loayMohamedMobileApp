import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design/app_colors.dart';
import '../../core/design/app_spacing.dart';
import '../../core/env/app_env.dart';
import '../../core/error/failures.dart';
import '../../core/utils/countries.dart';
import '../../core/utils/country_phone_field.dart';
import '../auth/presentation/auth_controller.dart';
import '../../app/app_shell.dart';
import '../providers.dart' as student_providers;

class CompleteProfileScreen extends ConsumerStatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  ConsumerState<CompleteProfileScreen> createState() =>
      _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends ConsumerState<CompleteProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _parentPhone = TextEditingController();
  final _school = TextEditingController();
  int _grade = 9;
  bool _loading = false;
  String? _avatarUrl;
  String? _localAvatarPath;
  Country _country = kDefaultCountry;
  Country _parentCountry = kDefaultCountry;
  bool _needsRealEmail = false;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authControllerProvider).user;
    if (user != null) {
      _name.text = user.name;
      _seedPhone(_phone, (cc) => _country = cc, user.phone);
      _seedPhone(_parentPhone, (cc) => _parentCountry = cc, user.parentPhone);
      _school.text = user.school ?? '';
      _grade = int.tryParse(user.grade ?? '') ?? 9;
      _avatarUrl = user.avatarUrl;
      _needsRealEmail = user.hasApplePrivateRelayEmail;
      // Only pre-fill the email if it's a real address.
      _email.text = _needsRealEmail ? '' : user.email;
    }
  }

  void _seedPhone(
      TextEditingController c, void Function(Country) setCC, String? raw) {
    final v = raw ?? '';
    if (v.startsWith('+')) {
      final found = kCountries.firstWhere(
        (cc) => v.startsWith(cc.code),
        orElse: () => kDefaultCountry,
      );
      setCC(found);
      c.text = v.substring(found.code.length);
    } else {
      c.text = normalizePhoneDigits(v);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _parentPhone.dispose();
    _school.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
    );
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() => _localAvatarPath = path);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_form.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      final repo = ref.read(authRepositoryProvider);
      await repo.updateProfile(
        name: _name.text.trim(),
        email: _needsRealEmail ? _email.text.trim() : null,
        phone: normalizePhoneDigits(_phone.text),
        countryCode: _country.code,
        parentPhone: normalizePhoneDigits(_parentPhone.text),
        parentCountryCode: _parentCountry.code,
        school: _school.text.trim(),
        grade: _grade,
      );
      if ((_localAvatarPath ?? '').isNotEmpty) {
        await repo.uploadProfileImage(_localAvatarPath!);
      }
      await ref.read(authControllerProvider.notifier).refreshMe();
      // Refresh student-side caches so the new identity is reflected on home.
      ref
        ..invalidate(student_providers.dashboardProvider)
        ..invalidate(student_providers.subjectsProvider)
        ..invalidate(student_providers.enrolledSubjectsProvider)
        ..invalidate(student_providers.enrollmentsProvider)
        ..invalidate(student_providers.contentsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated successfully')),
      );
      // The CompleteProfileScreen is set as MaterialApp.home, so popping
      // does nothing. Push-replace into the main app shell instead.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute<void>(builder: (_) => const AppShell()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e is AppFailure ? e.message : e.toString())),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Center(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                  backgroundImage: _localAvatarPath != null
                      ? FileImage(File(_localAvatarPath!))
                      : ((AppEnv.I.resolveMediaUrl(_avatarUrl) ?? '').isNotEmpty
                          ? NetworkImage(AppEnv.I.resolveMediaUrl(_avatarUrl)!)
                          : null) as ImageProvider<Object>?,
                  child:
                      ((AppEnv.I.resolveMediaUrl(_avatarUrl) ?? '').isEmpty &&
                              _localAvatarPath == null)
                          ? const Icon(Icons.person_rounded,
                              size: 44, color: AppColors.primary)
                          : null,
                ),
                Positioned(
                  right: -4,
                  bottom: -4,
                  child: IconButton.filled(
                    onPressed: _loading ? null : _pickAvatar,
                    icon: const Icon(Icons.camera_alt_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Form(
            key: _form,
            child: Column(
              children: [
                TextFormField(
                  controller: _name,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (v) => (v?.trim().isNotEmpty ?? false)
                      ? null
                      : 'Name is required',
                ),
                if (_needsRealEmail) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.08),
                      border: Border.all(
                          color: Colors.orange.withValues(alpha: 0.4)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            color: Colors.orange, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'You signed in with Apple using "Hide My Email". Please enter your real email so we can reach you about your courses, payments and notifications.',
                            style: TextStyle(fontSize: 12.5, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Real email address',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                    validator: (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Email is required';
                      final ok =
                          RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
                      if (!ok) return 'Enter a valid email address';
                      if (s
                          .toLowerCase()
                          .endsWith('@privaterelay.appleid.com')) {
                        return 'Please enter your real email, not the Apple relay address';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                CountryPhoneField(
                  country: _country,
                  controller: _phone,
                  onCountryChanged: (c) => setState(() => _country = c),
                  label: 'Student mobile',
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                CountryPhoneField(
                  country: _parentCountry,
                  controller: _parentPhone,
                  onCountryChanged: (c) => setState(() => _parentCountry = c),
                  label: 'Parent mobile',
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
                  validator: (v) => (v?.trim().isNotEmpty ?? false)
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
                          value: g, child: Text('Grade $g')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _grade = v);
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: const Icon(Icons.check_rounded),
                    label: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.3),
                          )
                        : const Text('Save Profile'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
