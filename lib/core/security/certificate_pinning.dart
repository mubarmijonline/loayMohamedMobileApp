import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../logging/app_logger.dart';

/// SPKI certificate pinning for the API host.
///
/// Pins the **Subject Public Key Info** hash rather than the whole certificate,
/// so a routine renewal that keeps the same key pair does not break the app.
///
/// ## Configuring the pins — required before release
///
/// The pin set below is **empty by default, which disables pinning**. That is
/// deliberate: a wrong pin bricks every installed copy of the app until the
/// next store review, which is a far worse outage than no pinning. Shipping
/// without pins is a known, logged gap; shipping with a wrong pin is a
/// recall.
///
/// Get the current pin with:
///
/// ```bash
/// openssl s_client -servername loaymotawie.com -connect loaymotawie.com:443 \
///   | openssl x509 -pubkey -noout \
///   | openssl pkey -pubin -outform der \
///   | openssl dgst -sha256 -binary \
///   | openssl enc -base64
/// ```
///
/// Then pass them at build time — never hardcode them into a committed file,
/// so rotating a pin does not require a code change:
///
/// ```bash
/// flutter build apk --release \
///   --dart-define=SPKI_PINS=<primary>,<backup>
/// ```
///
/// **Always ship at least two pins.** The second must be the SPKI of the *next*
/// key (or the issuing CA's), generated before the current cert expires. One
/// pin plus one rotation equals a dead installed base.
class CertificatePinning {
  CertificatePinning({Set<String>? pins, String? host})
      : pins = pins ?? _pinsFromEnvironment(),
        host = host ?? '';

  /// Base64 SHA-256 hashes of accepted SPKIs. Empty = pinning disabled.
  final Set<String> pins;

  /// Host these pins apply to. Other hosts (Bunny, Drive, Cloudflare) are left
  /// to normal system validation — we do not control their rotation.
  final String host;

  static const String _rawPins = String.fromEnvironment('SPKI_PINS');

  static Set<String> _pinsFromEnvironment() => _rawPins
      .split(',')
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toSet();

  bool get isEnabled => pins.isNotEmpty;

  /// Computes the base64 SHA-256 of a certificate's SPKI.
  ///
  /// `X509Certificate` in `dart:io` exposes only the DER of the whole
  /// certificate, so the SPKI is located by scanning the DER for the
  /// `SubjectPublicKeyInfo` structure. This is why the value must be verified
  /// against the `openssl` output above before shipping — see [debugPinFor].
  static String? spkiHashOf(X509Certificate cert) {
    try {
      final der = cert.der;
      final spki = _extractSpki(der);
      if (spki == null) return null;
      return base64.encode(sha256.convert(spki).bytes);
    } catch (_) {
      return null;
    }
  }

  /// Locates the SubjectPublicKeyInfo inside a DER-encoded certificate.
  ///
  /// SPKI is a SEQUENCE whose first element is an AlgorithmIdentifier SEQUENCE
  /// containing an OID. Rather than write a full ASN.1 parser we search for the
  /// well-known algorithm-identifier prefixes and walk back to the enclosing
  /// SEQUENCE header — enough for the RSA and EC certs a public CA issues.
  static List<int>? _extractSpki(List<int> der) {
    // AlgorithmIdentifier headers for rsaEncryption and id-ecPublicKey.
    const rsa = [
      0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, //
      0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00,
    ];
    const ec = [
      0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, //
      0x3d, 0x02, 0x01,
    ];
    for (final marker in [rsa, ec]) {
      final at = _indexOf(der, marker);
      if (at < 0) continue;
      // The SPKI SEQUENCE header sits immediately before the algorithm id.
      // Walk back over the (1-4 byte) length encoding to the 0x30 tag.
      for (var back = 2; back <= 5 && at - back >= 0; back++) {
        final start = at - back;
        if (der[start] != 0x30) continue;
        final len = _derLengthAt(der, start + 1);
        if (len == null) continue;
        final end = len.headerEnd + len.value;
        if (end > der.length) continue;
        // The located SEQUENCE must actually contain the algorithm id.
        if (len.headerEnd <= at && end >= at + marker.length) {
          return der.sublist(start, end);
        }
      }
    }
    return null;
  }

  static ({int value, int headerEnd})? _derLengthAt(List<int> b, int i) {
    if (i >= b.length) return null;
    final first = b[i];
    if (first < 0x80) return (value: first, headerEnd: i + 1);
    final count = first & 0x7f;
    if (count == 0 || count > 4 || i + count >= b.length) return null;
    var v = 0;
    for (var k = 1; k <= count; k++) {
      v = (v << 8) | b[i + k];
    }
    return (value: v, headerEnd: i + 1 + count);
  }

  static int _indexOf(List<int> haystack, List<int> needle) {
    outer:
    for (var i = 0; i + needle.length <= haystack.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) continue outer;
      }
      return i;
    }
    return -1;
  }

  /// The `badCertificateCallback` body.
  ///
  /// Returning `true` accepts a certificate the system already rejected, so
  /// this must only ever return true for a certificate whose SPKI we pinned.
  /// When pinning is disabled it returns `false` — i.e. it never weakens the
  /// default validation, it only ever adds a constraint.
  bool allowCertificate(X509Certificate cert, String certHost, int port) {
    if (!isEnabled) return false;
    if (host.isNotEmpty && certHost != host) return false;
    final hash = spkiHashOf(cert);
    if (hash == null) {
      AppLogger.I.e('Pinning: could not read SPKI for $certHost — rejecting');
      return false;
    }
    final ok = pins.contains(hash);
    if (!ok) {
      // Never log the served hash in release: on a MITM it is attacker input,
      // and in the logs it looks like a pin worth copying into the app.
      AppLogger.I.e('Pinning: SPKI mismatch for $certHost — rejecting');
    }
    return ok;
  }

  /// Validates a certificate the system already accepted.
  ///
  /// `badCertificateCallback` only fires when validation *fails*, so pinning
  /// enforced there alone would never see a valid-but-unpinned certificate —
  /// exactly the MITM case where a proxy CA is trusted by the device. This is
  /// the check that closes that hole; wire it from an interceptor or an
  /// `HttpClient` connection callback.
  bool isPinned(X509Certificate cert) =>
      !isEnabled || pins.contains(spkiHashOf(cert) ?? '');

  /// Prints the pin for a live host. Debug helper for generating the values
  /// that go into `--dart-define=SPKI_PINS`.
  static Future<String?> debugPinFor(String host) async {
    try {
      final client = HttpClient();
      String? found;
      client.badCertificateCallback = (cert, h, p) {
        found = spkiHashOf(cert);
        return true;
      };
      final req = await client.getUrl(Uri.parse('https://$host/'));
      final res = await req.close();
      found ??= spkiHashOf(res.certificate!);
      client.close(force: true);
      return found;
    } catch (e) {
      AppLogger.I.w('debugPinFor($host) failed: $e');
      return null;
    }
  }
}
