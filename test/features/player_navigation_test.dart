import 'package:flutter_test/flutter_test.dart';
import 'package:loay_mohamed_elearning/features/content_player/secure_web_player.dart';
import 'package:loay_mohamed_elearning/features/_shared/models.dart';

/// The navigation allowlist is the control that actually makes Drive's pop-out
/// button inert. Everything else around it — the injected CSS, the opaque
/// overlay — is a second layer over this one.
///
/// A regression here is invisible: the player still looks locked down and
/// still plays video, right up until a student taps the corner and lands on a
/// Drive page with a share button. So every escape route gets a test.
void main() {
  const driveUrl = 'https://drive.google.com/file/d/FILEID/preview';
  const policy = PlayerNavigationPolicy(loadedUrl: driveUrl);

  bool allows(String url) => policy.isAllowed(Uri.parse(url));

  group('the loaded page', () {
    test('is always permitted', () {
      expect(allows(driveUrl), isTrue);
    });

    test('bunny and cloudflare embeds load', () {
      const bunny = PlayerNavigationPolicy(
        loadedUrl: 'https://iframe.mediadelivery.net/embed/1/abc?token=t',
      );
      expect(
        bunny.isAllowed(
          Uri.parse('https://iframe.mediadelivery.net/embed/1/abc?token=t'),
        ),
        isTrue,
      );
      expect(allows('https://iframe.videodelivery.net/uid'), isTrue);
    });
  });

  group('escape routes are blocked', () {
    test('Drive pop-out targets that are not /preview', () {
      // These are what the pop-out button and the overflow menu actually
      // navigate to. Each one is a page with a share control on it.
      expect(allows('https://drive.google.com/file/d/FILEID/view'), isFalse);
      expect(allows('https://drive.google.com/file/d/FILEID/edit'), isFalse);
      expect(allows('https://drive.google.com/open?id=FILEID'), isFalse);
      expect(allows('https://drive.google.com/drive/my-drive'), isFalse);
      expect(
        allows('https://drive.google.com/uc?id=FILEID&export=download'),
        isFalse,
      );
    });

    test('the account chooser and sign-in', () {
      expect(allows('https://accounts.google.com/signin'), isFalse);
      expect(allows('https://accounts.google.com/AccountChooser'), isFalse);
    });

    test('app-launch schemes', () {
      // intent:// and market:// are how an Android WebView is talked into
      // handing off to another app.
      expect(
        allows('intent://drive.google.com/#Intent;scheme=https;end'),
        isFalse,
      );
      expect(
        allows('market://details?id=com.google.android.apps.docs'),
        isFalse,
      );
      expect(allows('itms-apps://apps.apple.com/app/id507874739'), isFalse);
    });

    test('share and compose targets', () {
      expect(
        allows('mailto:someone@example.com?body=https://drive...'),
        isFalse,
      );
      expect(allows('sms:+201200000000'), isFalse);
      expect(allows('tel:+201200000000'), isFalse);
      expect(allows('whatsapp://send?text=link'), isFalse);
    });

    test('about:blank, javascript: and data:', () {
      // about:blank is how a pop-out lands before it navigates on.
      expect(allows('about:blank'), isFalse);
      expect(
        allows('javascript:window.open("https://drive.google.com")'),
        isFalse,
      );
      expect(allows('data:text/html,<a href="x">x</a>'), isFalse);
    });

    test('local file and content URIs', () {
      expect(allows('file:///sdcard/Download/video.mp4'), isFalse);
      expect(allows('content://media/external/video/media/1'), isFalse);
    });

    test('an http downgrade', () {
      expect(
        allows('http://drive.google.com/file/d/FILEID/preview'),
        isFalse,
        reason: 'a downgrade is a misconfiguration or an attack',
      );
    });

    test('an arbitrary third-party host', () {
      expect(allows('https://evil.example.com/'), isFalse);
      expect(allows('https://youtube-dl.example.com/grab?u=...'), isFalse);
    });

    test('a lookalike host that merely contains an allowed name', () {
      // Suffix matching must be on a dot boundary, or
      // `drive.google.com.evil.com` sails through.
      expect(allows('https://drive.google.com.evil.com/file'), isFalse);
      expect(allows('https://notmediadelivery.net/embed/1/x'), isFalse);
      expect(allows('https://mediadelivery.net.evil.com/x'), isFalse);
    });
  });

  group('legitimate sub-resources still load', () {
    test('media and asset hosts the players pull from', () {
      expect(allows('https://vz-abc.b-cdn.net/segment.ts'), isTrue);
      expect(
        allows('https://customer-x.cloudflarestream.com/uid/manifest'),
        isTrue,
      );
      expect(
        allows('https://rr1---sn-abc.googlevideo.com/videoplayback'),
        isTrue,
      );
      expect(allows('https://lh3.googleusercontent.com/thumb'), isTrue);
      expect(allows('https://ssl.gstatic.com/docs/player.js'), isTrue);
    });

    test('a Drive preview on a subdomain', () {
      expect(allows('https://drive.google.com/file/d/OTHER/preview'), isTrue);
    });
  });

  group('watermark identity', () {
    test('matches the backend format for Bunny', () {
      // API_BRIEF §6: `Full Name · +20… · <user_id>`.
      expect(
        SecureWebPlayer.buildWatermark(
          fullName: 'Sara Ali',
          phone: '+201200000000',
          userId: '65f0abc',
        ),
        'Sara Ali · +201200000000 · 65f0abc',
      );
    });

    test('omits a missing phone rather than leaving a dangling separator', () {
      expect(
        SecureWebPlayer.buildWatermark(fullName: 'Sara Ali', userId: '65f0abc'),
        'Sara Ali · 65f0abc',
      );
    });
  });

  group('signed embed expiry', () {
    test('a Bunny embed goes stale so it can be re-minted', () {
      final fresh = ContentEmbed.fromJson(const {
        'embed_url': 'https://iframe.mediadelivery.net/embed/1/x?token=t',
        'provider': 'bunny',
      });
      expect(fresh.isStale, isFalse);

      // An embed with no fetch time is treated as stale rather than trusted.
      const unknown = ContentEmbed(
        embedUrl: 'https://iframe.mediadelivery.net/embed/1/x',
        provider: VideoProvider.bunny,
      );
      expect(unknown.isStale, isTrue);
    });

    test('drive and cloudflare embeds never expire', () {
      const drive = ContentEmbed(
        embedUrl: 'https://drive.google.com/file/d/x/preview',
        provider: VideoProvider.drive,
      );
      expect(drive.isStale, isFalse);
      expect(drive.provider.isSigned, isFalse);
    });
  });

  group('Bunny share controls are disabled client-side', () {
    // The web portal appends these server-side (api.py:632). The mobile
    // /embed route does not, so the client must — otherwise Bunny renders a
    // share button and a copy-link affordance inside a player whose entire
    // purpose is that the video cannot leave the app.
    ContentEmbed bunny(String url) => ContentEmbed(
          embedUrl: url,
          provider: VideoProvider.bunny,
          fetchedAt: DateTime.now(),
        );

    test('share, sharing and pip are all disabled', () {
      final out = SecureWebPlayer.playbackUrl(
        bunny('https://iframe.mediadelivery.net/embed/1/abc?token=t&expires=9'),
      );
      final q = Uri.parse(out).queryParameters;
      expect(q['share'], 'false');
      expect(q['sharing'], 'false');
      expect(q['pip'], 'false');
    });

    test('the signed token and expiry are preserved', () {
      final out = SecureWebPlayer.playbackUrl(
        bunny(
            'https://iframe.mediadelivery.net/embed/1/abc?token=SIG&expires=9'),
      );
      final q = Uri.parse(out).queryParameters;
      // Dropping either of these turns a working signed URL into a 403.
      expect(q['token'], 'SIG');
      expect(q['expires'], '9');
    });

    test('works on an embed URL that has no query string', () {
      final out = SecureWebPlayer.playbackUrl(
        bunny('https://iframe.mediadelivery.net/embed/1/abc'),
      );
      expect(Uri.parse(out).queryParameters['share'], 'false');
    });

    test('drive and cloudflare URLs are left untouched', () {
      const drive = ContentEmbed(
        embedUrl: 'https://drive.google.com/file/d/x/preview',
        provider: VideoProvider.drive,
      );
      expect(SecureWebPlayer.playbackUrl(drive), drive.embedUrl);

      const cf = ContentEmbed(
        embedUrl: 'https://iframe.videodelivery.net/uid',
        provider: VideoProvider.cloudflare,
      );
      expect(SecureWebPlayer.playbackUrl(cf), cf.embedUrl);
    });

    test('the loaded URL is still allowed by its own navigation policy', () {
      // The policy is built from the transformed URL. If it were built from
      // the raw embed, the player's own page would look foreign to the
      // allowlist and the video would refuse to load.
      final loaded = SecureWebPlayer.playbackUrl(
        bunny('https://iframe.mediadelivery.net/embed/1/abc?token=t'),
      );
      final policy = PlayerNavigationPolicy(loadedUrl: loaded);
      expect(policy.isAllowed(Uri.parse(loaded)), isTrue);
    });
  });

  _authWallTests();
  _streamUrlTests();
}

void _authWallTests() {
  const policy = PlayerNavigationPolicy(
    loadedUrl: 'https://drive.google.com/file/d/FILEID/preview',
  );

  group('sign-in redirects are recognised, not just blocked', () {
    // A Drive file that is not shared as "Anyone with the link" redirects the
    // WebView to accounts.google.com. The allowlist refuses it, which is
    // correct — but the player must be able to tell that apart from a network
    // failure, or it tells the student to check their connection while the
    // real problem is a sharing setting only the teacher can change.
    test('google sign-in hosts are identified', () {
      expect(
        PlayerNavigationPolicy.isAuthWallHost('accounts.google.com'),
        isTrue,
      );
      expect(
        PlayerNavigationPolicy.isAuthWallHost('ACCOUNTS.GOOGLE.COM'),
        isTrue,
        reason: 'host comparison must be case-insensitive',
      );
    });

    test('they are still blocked', () {
      expect(policy.isAllowed(Uri.parse('https://accounts.google.com/signin')),
          isFalse);
    });

    test('an ordinary blocked host is not mistaken for an auth wall', () {
      expect(
          PlayerNavigationPolicy.isAuthWallHost('evil.example.com'), isFalse);
      expect(
          PlayerNavigationPolicy.isAuthWallHost('drive.google.com'), isFalse);
    });

    test('a lookalike auth host does not match', () {
      expect(
        PlayerNavigationPolicy.isAuthWallHost('accounts.google.com.evil.com'),
        isFalse,
      );
    });
  });
}

void _streamUrlTests() {
  const origin = 'https://loaymotawie.com';

  /// What the repository actually hands the player: parsed, then resolved
  /// against our API origin.
  ContentEmbed embed(Map<String, dynamic> j) =>
      ContentEmbed.fromJson(j).resolvedAgainst(origin);

  group('stream_url selection (API_BRIEF §6)', () {
    test('Drive plays the proxy, not the public preview URL', () {
      final e = embed({
        'provider': 'drive',
        'embed_url': 'https://drive.google.com/file/d/SECRET/preview',
        'stream_url': '/api/v1/student/content/abc/drive-stream',
        'watermark': 'Sara Ali · +20 · 65f0',
      });
      expect(
        e.playbackUrl,
        '$origin/api/v1/student/content/abc/drive-stream',
      );
      expect(e.needsWebView, isFalse,
          reason: 'the proxy is raw mp4 — a WebView would be the wrong tool '
              'and would reintroduce Google chrome');
      expect(e.needsAuthHeader, isTrue);
    });

    test('the public Drive URL is never what gets played', () {
      final e = embed({
        'provider': 'drive',
        'embed_url': 'https://drive.google.com/file/d/SECRET/preview',
        'stream_url': '/api/v1/student/content/abc/drive-stream',
      });
      // Anyone holding the preview URL can watch without an account, so it
      // must not reach the player or any log line.
      expect(e.playbackUrl, isNot(contains('drive.google.com')));
      expect(e.toString(), isNot(contains('SECRET')));
    });

    test('Drive falls back to the WebView when the proxy is absent', () {
      // Older backends have no stream_url. Degrade rather than show nothing.
      final e = embed({
        'provider': 'drive',
        'embed_url': 'https://drive.google.com/file/d/x/preview',
      });
      expect(e.needsWebView, isTrue);
      expect(e.needsAuthHeader, isFalse);
      expect(e.playbackUrl, e.embedUrl);
    });

    test('Bunny and Cloudflare still use the WebView, with no auth header', () {
      for (final p in ['bunny', 'cloudflare']) {
        final e = embed({
          'provider': p,
          'embed_url': 'https://iframe.example.net/x',
          'stream_url': 'https://iframe.example.net/x',
        });
        expect(e.needsWebView, isTrue, reason: '$p is an iframe');
        expect(
          e.needsAuthHeader,
          isFalse,
          reason: 'our bearer token must never be sent to a third-party '
              'iframe host',
        );
      }
    });

    test('watermark now arrives for every provider', () {
      final e = embed({
        'provider': 'drive',
        'stream_url': '/api/v1/student/content/abc/drive-stream',
        'watermark': 'Sara Ali · +201200000000 · 65f0abc',
      });
      expect(e.watermark, 'Sara Ali · +201200000000 · 65f0abc');
    });
  });

  // ── The black-screen regression ────────────────────────────────────────
  //
  // Symptom: the player area rendered black while the watermark and the
  // screenshot blocker worked, so everything *around* the video was clearly
  // alive. Two independent defects both produced it, and both are silent —
  // no exception, no error view, just a black rectangle.
  group('a relative stream_url is resolved before it reaches a player', () {
    test('resolvedAgainst turns the path into something openable', () {
      final e = embed({
        'provider': 'drive',
        'stream_url': '/api/v1/student/content/abc/drive-stream',
      });
      final u = Uri.parse(e.playbackUrl);
      expect(u.hasScheme, isTrue);
      expect(u.hasAuthority, isTrue,
          reason: 'video_player and WebView cannot open a schemeless URI, and '
              'neither reports a useful error when handed one');
      expect(u.host, 'loaymotawie.com');
      expect(u.path, '/api/v1/student/content/abc/drive-stream');
    });

    test('an absolute stream_url is left exactly as the backend sent it', () {
      final e = embed({
        'provider': 'bunny',
        'stream_url': 'https://iframe.mediadelivery.net/embed/1/a?token=t',
      });
      expect(
          e.playbackUrl, 'https://iframe.mediadelivery.net/embed/1/a?token=t');
    });

    test('an unresolved embed never claims the auth header', () {
      // fromJson alone — no origin known. Guessing "ours" here would post the
      // bearer token to whatever host the URL turns out to name.
      final e = ContentEmbed.fromJson({
        'provider': 'drive',
        'stream_url': '/api/v1/student/content/abc/drive-stream',
      });
      expect(e.needsAuthHeader, isFalse);
    });
  });

  group('the player is chosen by URL ownership, not the provider string', () {
    test('a missing provider still routes the proxy to the native player', () {
      // The regression: `provider` absent -> VideoProvider.unknown ->
      // needsWebView -> the WebView branch loaded `embed_url`, which for a
      // private Drive file is Google's auth wall. Black frame, no error.
      final e = embed({
        'embed_url': 'https://drive.google.com/file/d/SECRET/preview',
        'stream_url': '/api/v1/student/content/abc/drive-stream',
      });
      expect(e.provider, VideoProvider.unknown);
      expect(e.isProxied, isTrue);
      expect(e.needsWebView, isFalse);
      expect(e.needsAuthHeader, isTrue);
    });

    test('an unrecognised provider name is handled the same way', () {
      final e = embed({
        'provider': 'gdrive',
        'stream_url': '/api/v1/student/content/abc/drive-stream',
      });
      expect(e.needsWebView, isFalse);
    });

    test('a third-party host is never treated as ours', () {
      for (final host in [
        'https://evil.example.com/x',
        'https://loaymotawie.com.evil.example/x',
        'http://loaymotawie.com/x', // scheme is part of the origin
      ]) {
        final e = embed({'provider': 'drive', 'stream_url': host});
        expect(e.isProxied, isFalse, reason: host);
        expect(e.needsAuthHeader, isFalse, reason: host);
      }
    });
  });

  group('SecureWebPlayer.playbackUrl loads the stream URL', () {
    test('non-Bunny embeds load stream_url, not embed_url', () {
      // It used to return `embed.embedUrl` unconditionally, so a WebView-bound
      // embed played the public preview instead of the proxy.
      final e = embed({
        'provider': 'cloudflare',
        'embed_url': 'https://old.example.net/legacy',
        'stream_url': 'https://iframe.example.net/current',
      });
      expect(
        SecureWebPlayer.playbackUrl(e),
        'https://iframe.example.net/current',
      );
    });

    test('falls back to embed_url when there is no stream_url', () {
      final e = embed({
        'provider': 'cloudflare',
        'embed_url': 'https://old.example.net/legacy',
      });
      expect(SecureWebPlayer.playbackUrl(e), 'https://old.example.net/legacy');
    });

    test('Bunny keeps its share-suppressing params on the stream URL', () {
      final e = embed({
        'provider': 'bunny',
        'embed_url': 'https://iframe.mediadelivery.net/embed/1/old',
        'stream_url': 'https://iframe.mediadelivery.net/embed/1/new?token=t',
      });
      final out = SecureWebPlayer.playbackUrl(e);
      expect(out, contains('/new'));
      expect(out, contains('token=t'));
      expect(out, contains('share=false'));
      expect(out, contains('pip=false'));
    });
  });

  test('hasVideo is false when the backend sends neither URL', () {
    final e = embed({'provider': 'drive'});
    expect(e.hasVideo, isFalse,
        reason: 'an empty URL must reach the error view, not a black WebView');
  });
}
