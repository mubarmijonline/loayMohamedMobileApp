import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/app_colors.dart';
import '../design/app_spacing.dart';
import 'countries.dart';
import '../../core/design/app_palette.dart';

/// Reusable country-code + phone-number field rendered as a Row of two
/// independent inputs: a tappable country picker on the left and a normal
/// `TextFormField` on the right. This avoids the prefixIcon layout pitfalls
/// that can hide the text field on tight widths.
class CountryPhoneField extends StatelessWidget {
  const CountryPhoneField({
    super.key,
    required this.country,
    required this.controller,
    required this.onCountryChanged,
    this.label = 'Mobile number',
    this.hint = '1024527771',
    this.icon = Icons.phone_iphone_rounded,
    this.validator,
    this.textInputAction,
    this.onSubmitted,
    this.autofillHints,
  });

  final Country country;
  final TextEditingController controller;
  final ValueChanged<Country> onCountryChanged;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Country picker pill
        _CountryPickerButton(
          country: country,
          onPick: () async {
            final picked = await showCountryPicker(context, selected: country);
            if (picked != null) onCountryChanged(picked);
          },
        ),
        const SizedBox(width: AppSpacing.sm),
        // Phone number field
        Expanded(
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.phone,
            textInputAction: textInputAction,
            autofillHints: autofillHints,
            onFieldSubmitted: onSubmitted,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(15),
            ],
            decoration: InputDecoration(
              labelText: label,
              hintText: hint,
              prefixIcon: Icon(icon),
            ),
            validator: validator ??
                (v) {
                  final s = (v ?? '').trim();
                  if (s.isEmpty) return 'Mobile is required';
                  if (s.length < 6) return 'Mobile is too short';
                  return null;
                },
          ),
        ),
      ],
    );
  }
}

class _CountryPickerButton extends StatelessWidget {
  const _CountryPickerButton({required this.country, required this.onPick});
  final Country country;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: onPick,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: context.palette.divider),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(country.flag, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 6),
            Text(
              country.code,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down_rounded,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
                size: 20),
          ],
        ),
      ),
    );
  }
}
