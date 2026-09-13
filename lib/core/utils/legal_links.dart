import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pages on loaymotawie.com that the app itself has to link to.
///
/// Apple (guideline 5.1.1(i)) and Google Play (User Data policy) both require
/// the privacy policy to be reachable from inside the app, not only from the
/// store listing. The address is fixed rather than built from
/// `AppEnv.apiBaseUrl`, so a staging build still opens the published policy,
/// and it must match the URL entered in App Store Connect and Play Console.
class LegalLinks {
  LegalLinks._();

  static final Uri privacyPolicy = Uri.parse('https://loaymotawie.com/privacy');

  /// Opens [uri] over the app (SFSafariViewController on iOS, a Custom Tab on
  /// Android), and says so if nothing could open it.
  static Future<void> open(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    var opened = false;
    try {
      opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    } catch (_) {
      // No browser at all surfaces as a PlatformException on some devices.
    }
    if (!opened) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Could not open ${uri.host}${uri.path}')),
      );
    }
  }
}
