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
              InternationalNumberFormatter(onCountry: onCountryChanged),
              // 15 digits is the E.164 maximum, plus a leading `+`.
              LengthLimitingTextInputFormatter(16),
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
            // Letters, not the flag emoji: iOS 26 draws flag emoji as empty
            // boxes in this app's fonts, and some Android devices ship no
            // flag glyphs either.
            Text(
              country.isoCode,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: context.palette.textSecondary,
              ),
            ),
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

/// Keeps the number field to digits, while letting a number arrive in
/// international form.
///
/// A pasted `+1 202-555-0124` (or `00 1 …`) switches the picker to that
/// country and leaves the national digits, `2025550124`. A `+` typed by hand
/// stays, and [toE164] sends that number as written.
///
/// The field used to strip everything but digits, so the paste became
/// `12025550124` under the default `+20`, and the server was sent
/// `+2012025550124`: "Invalid phone number." App Review copies numbers from
/// the review notes, so this is the first thing they would hit.
@visibleForTesting
class InternationalNumberFormatter extends TextInputFormatter {
  InternationalNumberFormatter({required this.onCountry});

  final ValueChanged<Country> onCountry;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.replaceAll(RegExp(r'[\s\-().]'), '');
    final String? international = raw.startsWith('+')
        ? raw.substring(1)
        : raw.startsWith('00')
            ? raw.substring(2)
            : null;
    if (international == null) {
      // Plain digits: Flutter's own filter, which keeps the cursor in place.
      return FilteringTextInputFormatter.digitsOnly
          .formatEditUpdate(oldValue, newValue);
    }

    final digits = _digits(international);
    // Several characters at once is a paste or autofill: hand the country to
    // the picker. One at a time is typing, which keeps the `+`.
    final pasted = newValue.text.length - oldValue.text.length > 1;
    final country = pasted ? countryForDialDigits(digits) : null;
    if (country == null) return _collapsed('+$digits');

    // Not during the formatter's own pass: the callback rebuilds the parent.
    Future.microtask(() => onCountry(country));
    return _collapsed(digits.substring(country.code.length - 1));
  }

  static String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  static TextEditingValue _collapsed(String text) => TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
}
