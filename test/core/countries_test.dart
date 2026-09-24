import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/utils/countries.dart';

void main() {
  test('isoCode spells out the flag emoji', () {
    expect(kDefaultCountry.isoCode, 'EG');
    expect(kCountries.every((c) => c.isoCode.length == 2), isTrue);

    // Not a flag: better an empty badge than half-decoded characters.
    expect(const Country(code: '+1', flag: 'x', name: 'Nowhere').isoCode, '');
  });
}
