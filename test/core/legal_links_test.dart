import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/core/utils/legal_links.dart';

void main() {
  test('privacy policy URL is the one entered in both store consoles', () {
    // App Store Connect and Play Console point at this exact address
    // (docs/store/SUBMISSION_GUIDE.md). Changing it here alone would leave the
    // app and the listings disagreeing.
    expect(
      LegalLinks.privacyPolicy.toString(),
      'https://loaymotawie.com/privacy',
    );
  });
}
