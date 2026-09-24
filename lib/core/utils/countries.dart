import 'package:flutter/material.dart';

/// Lightweight country code list. Egypt first since this is the primary market.
class Country {
  const Country({required this.code, required this.flag, required this.name});
  final String code; // dial code with leading +
  final String flag;
  final String name;

  /// `EG` for `🇪🇬`. A flag emoji is two regional-indicator letters, and iOS 26
  /// draws those as empty boxes in this app's fonts, so the picker shows the
  /// letters themselves. Empty when [flag] is not a two-letter flag.
  String get isoCode {
    const first = 0x1F1E6; // 🇦
    final runes = flag.runes.toList();
    if (runes.length != 2 || runes.any((r) => r < first || r > first + 25)) {
      return '';
    }
    return runes.map((r) => String.fromCharCode(0x41 + r - first)).join();
  }
}

const kCountries = <Country>[
  Country(code: '+20', flag: '🇪🇬', name: 'Egypt'),
  Country(code: '+966', flag: '🇸🇦', name: 'Saudi Arabia'),
  Country(code: '+971', flag: '🇦🇪', name: 'United Arab Emirates'),
  Country(code: '+965', flag: '🇰🇼', name: 'Kuwait'),
  Country(code: '+974', flag: '🇶🇦', name: 'Qatar'),
  Country(code: '+973', flag: '🇧🇭', name: 'Bahrain'),
  Country(code: '+968', flag: '🇴🇲', name: 'Oman'),
  Country(code: '+962', flag: '🇯🇴', name: 'Jordan'),
  Country(code: '+961', flag: '🇱🇧', name: 'Lebanon'),
  Country(code: '+970', flag: '🇵🇸', name: 'Palestine'),
  Country(code: '+963', flag: '🇸🇾', name: 'Syria'),
  Country(code: '+964', flag: '🇮🇶', name: 'Iraq'),
  Country(code: '+212', flag: '🇲🇦', name: 'Morocco'),
  Country(code: '+213', flag: '🇩🇿', name: 'Algeria'),
  Country(code: '+216', flag: '🇹🇳', name: 'Tunisia'),
  Country(code: '+218', flag: '🇱🇾', name: 'Libya'),
  Country(code: '+249', flag: '🇸🇩', name: 'Sudan'),
  Country(code: '+44', flag: '🇬🇧', name: 'United Kingdom'),
  Country(code: '+1', flag: '🇺🇸', name: 'United States'),
  Country(code: '+33', flag: '🇫🇷', name: 'France'),
  Country(code: '+49', flag: '🇩🇪', name: 'Germany'),
  Country(code: '+90', flag: '🇹🇷', name: 'Turkey'),
];

const kDefaultCountry = Country(code: '+20', flag: '🇪🇬', name: 'Egypt');

Country countryFromCode(String code) =>
    kCountries.firstWhere((c) => c.code == code, orElse: () => kDefaultCountry);

/// Strip spaces and a leading 0, return digits only.
String normalizePhoneDigits(String raw) {
  var s = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (s.startsWith('0')) s = s.substring(1);
  return s.replaceAll(RegExp(r'[^0-9]'), '');
}

/// Build E.164 from a country code + local number.
String toE164(String countryCode, String localNumber) {
  final cc = countryCode.startsWith('+') ? countryCode : '+$countryCode';
  return '$cc${normalizePhoneDigits(localNumber)}';
}

/// Show a bottom-sheet country picker, returns the picked country.
Future<Country?> showCountryPicker(BuildContext context, {Country? selected}) {
  return showModalBottomSheet<Country>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final controller = TextEditingController();
      return StatefulBuilder(
        builder: (ctx, setState) {
          final query = controller.text.trim().toLowerCase();
          final items = kCountries.where((c) {
            if (query.isEmpty) return true;
            return c.name.toLowerCase().contains(query) ||
                c.code.contains(query);
          }).toList();
          return SafeArea(
            top: false,
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: TextField(
                      controller: controller,
                      decoration: const InputDecoration(
                        hintText: 'Search country or code',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final c = items[i];
                        final isSelected = selected?.code == c.code;
                        return ListTile(
                          leading: Text(c.flag,
                              style: const TextStyle(fontSize: 22)),
                          title: Text(c.name),
                          trailing: Text(
                            c.code,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                            ),
                          ),
                          selected: isSelected,
                          onTap: () => Navigator.of(ctx).pop(c),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
