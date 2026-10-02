import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/utils/countries.dart';
import 'package:loay_mohamed_elearning/core/utils/country_phone_field.dart';

void main() {
  test('isoCode spells out the flag emoji', () {
    expect(kDefaultCountry.isoCode, 'EG');
    expect(kCountries.every((c) => c.isoCode.length == 2), isTrue);

    // Not a flag: better an empty badge than half-decoded characters.
    expect(const Country(code: '+1', flag: 'x', name: 'Nowhere').isoCode, '');
  });

  test('toE164 sends a number given in international form as written', () {
    // App Review pasted +1 202-555-0124 under the default Egypt picker; the
    // app sent +2012025550124 and the server said "Invalid phone number."
    expect(toE164('+20', '+1 202-555-0124'), '+12025550124');
    expect(toE164('+20', '00 1 202 555 0124'), '+12025550124');
    // Unchanged: national digits under the picker, trunk zero dropped.
    expect(toE164('+1', '2025550124'), '+12025550124');
    expect(toE164('+20', '01012345678'), '+201012345678');
  });

  test('countryForDialDigits finds the country from its dial code', () {
    expect(countryForDialDigits('12025550124')?.name, 'United States');
    expect(countryForDialDigits('201012345678')?.name, 'Egypt');
    expect(countryForDialDigits('966501234567')?.name, 'Saudi Arabia');
    expect(countryForDialDigits('8613800000000'), isNull);
  });

  group('InternationalNumberFormatter', () {
    TextEditingValue edit(
      InternationalNumberFormatter f,
      String before,
      String after,
    ) =>
        f.formatEditUpdate(
          TextEditingValue(text: before),
          TextEditingValue(text: after),
        );

    test('a pasted international number moves its code to the picker',
        () async {
      Country? picked;
      final f = InternationalNumberFormatter(onCountry: (c) => picked = c);
      expect(edit(f, '', '+1 202-555-0124').text, '2025550124');
      await Future<void>.delayed(Duration.zero);
      expect(picked?.name, 'United States');
    });

    test('a + typed by hand stays, so toE164 can honour it', () {
      final f = InternationalNumberFormatter(onCountry: (_) {});
      expect(edit(f, '', '+').text, '+');
      expect(edit(f, '+120255501', '+1202555012').text, '+1202555012');
    });

    test('anything else keeps to digits', () {
      final f = InternationalNumberFormatter(onCountry: (_) {});
      expect(edit(f, '', '010-1234 5678').text, '01012345678');
      expect(edit(f, '101', '101a').text, '101');
    });
  });
}
