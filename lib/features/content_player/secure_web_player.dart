import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../core/logging/app_logger.dart';
import '../../core/security/capture_event.dart';
import '../../core/security/screen_guard.dart';
import '../_shared/models.dart';
import 'watermark_layer.dart';

/// The one player widget, used by all three providers.
///
/// None of `bunny`, `cloudflare` or `drive` hands back a direct media file —
/// every one is an iframe — so `video_player`/`chewie` are the wrong tool and
/// everything renders in a locked-down `WebView`.
///
/// ## What actually stops the leak
///
/// The pop-out button is killed by **navigation lockdown**, not by hiding it.
/// [_onNavigationRequest] allows only the exact URL that was loaded plus the
/// player's own asset hosts, and refuses everything else — so tapping Drive's
/// "open in new window" does nothing at all. Hiding the control is then
/// cosmetic, and is done in two independent layers because either alone is
/// fragile:
///
///   1. Injected CSS/JS, best-effort. Google's class names change without
///      notice, so it is written to fail silently.
///   2. An opaque [AbsorbPointer] strip over the region where the control
///      sits. This does not depend on Google's DOM and is what we actually
///      rely on.
///
/// There is no code path from here that opens an external browser. `url_launcher`
/// is not imported and must not be.
class SecureWebPlayer extends StatefulWidget {
  const SecureWebPlayer({
    super.key,
    required this.embed,
    required this.watermark,
    required this.screenGuard,
    this.startAtSeconds = 0,
    this.onPositionChanged,
    this.onPlayingChanged,
    this.onEnded,
    this.onError,
    this.onExpired,
  });

  final ContentEmbed embed;

  /// `<full name> · <phone> · <user id>` — see [buildWatermark].
  final String watermark;

  final ScreenGuard screenGuard;
  final int startAtSeconds;

  final void Function(int position, int? duration)? onPositionChanged;
  final void Function(bool playing)? onPlayingChanged;
  final VoidCallback? onEnded;
  final VoidCallback? onError;

  /// A signed (Bunny) embed has outlived its TTL and needs re-fetching.
  final VoidCallback? onExpired;

  /// Builds the identity string drawn over every frame.
  ///
  /// Mirrors the format the backend uses for Bunny (API_BRIEF §6) so a Drive
  /// or Cloudflare video is watermarked identically to a Bunny one — the
  /// backend only returns `watermark` for Bunny, so the client builds it for
  /// the other two.
  static String buildWatermark({
    required String fullName,
    String? phone,
    required String userId,
  }) =>
      [fullName, phone, userId]
          .where((p) => p != null && p.trim().isNotEmpty)
          .map((p) => p!.trim())
          .join(' · ');

  /// The URL actually handed to the WebView.
  ///
  /// Bunny's iframe player ships a share button, a "copy link" affordance and
  /// picture-in-picture. The web portal disables all three by appending
  /// `share=false&sharing=false&pip=false` to the embed URL server-side
  /// (`api.py:632`), but the mobile endpoint returns the bare signed URL
  /// (backend confirmed 2026-09-06). So the client has to append them itself,
  /// or the player renders a share button we have spent this entire widget
  /// trying to make unreachable.
  ///
  /// Only applied to Bunny. Cloudflare and Drive have their own chrome, which
  /// the navigation allowlist and the overlay strip handle.
  ///
  /// Starts from [ContentEmbed.playbackUrl], not `embed_url`. Reading
  /// `embed_url` directly is what made a video render black: when `provider`
  /// was missing the embed took the WebView branch, and this method then
  /// loaded the *public* Drive preview of a private file — an auth wall — or,
  /// when the backend sent no `embed_url` at all, the empty string.
  static String playbackUrl(ContentEmbed embed) {
    final target = embed.playbackUrl;
    if (embed.provider != VideoProvider.bunny) return target;
    final uri = Uri.tryParse(target);
    if (uri == null) return target;
    // Do not clobber params the signature covers — add only what is missing.
    final params = Map<String, String>.from(uri.queryParameters);
    params['share'] = 'false';
    params['sharing'] = 'false';
    params['pip'] = 'false';
    return uri.replace(queryParameters: params).toString();
  }

  @override
  State<SecureWebPlayer> createState() => _SecureWebPlayerState();
}

class _SecureWebPlayerState extends State<SecureWebPlayer>
    with WidgetsBindingObserver {
  WebViewController? _controller;
  StreamSubscription<CaptureEvent>? _guardSub;
  Timer? _watermarkTimer;
  Timer? _ttlTimer;

  bool _loading = true;
  bool _failed = false;

  /// Set while a recording, mirror or external display is active. Blanks the
  /// video behind an opaque panel and pauses playback.
  CaptureEventType? _blockedBy;

  /// True once dispose() has started.
  ///
  /// Teardown navigates to `about:blank` to kill the page and any audio still
  /// playing in it. The allowlist blocks `about:` on purpose — it is where a
  /// pop-out lands — so without this flag the widget's own teardown was
  /// refused and the embed kept playing after the route popped. Confirmed in
  /// a device log: "Player blocked navigation to about://".
  bool _tearingDown = false;

  /// Set when a navigation to a sign-in host was refused, which means the
  /// content is not publicly viewable rather than that the network failed.
  bool _blockedByAuthWall = false;

  /// Watermark anchor, re-randomised on a timer so a static crop cannot
  /// remove it.
  Alignment _wmPrimary = Alignment.topLeft;
  Alignment _wmSecondary = Alignment.bottomRight;
  final _rng = math.Random();

  Uri get _loaded => Uri.parse(SecureWebPlayer.playbackUrl(widget.embed));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = _buildController();
    _listenToGuard();
    _startWatermarkDrift();
    _armTtl();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watermarkTimer?.cancel();
    _ttlTimer?.cancel();
    _guardSub?.cancel();
    // Tear the page down so no audio keeps playing after the route pops.
    // Must be flagged first — see [_tearingDown].
    _tearingDown = true;
    _controller?.loadRequest(Uri.parse('about:blank'));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _pause();
    } else {
      // A signed URL may have expired while we were away.
      if (widget.embed.isStale) widget.onExpired?.call();
    }
  }

  // ───────────────────────── capture blocking ─────────────────────────

  void _listenToGuard() {
    _guardSub = widget.screenGuard.events.listen((e) {
      if (!mounted) return;
      if (e.type.blocksPlayback) {
        _pause();
        setState(() => _blockedBy = e.type);
      } else if (e.type.clearsBlock) {
        setState(() => _blockedBy = null);
      } else if (e.type == CaptureEventType.screenshot) {
        _warnAboutScreenshot();
      }
    });
  }

  void _warnAboutScreenshot() {
    // The image already exists — this cannot be undone. The point is that the
    // student knows the capture was recorded against their name.
    final count = widget.screenGuard.screenshotCount;
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade900,
        duration: const Duration(seconds: 5),
        content: Text(
          count > 1
              ? 'Screenshots are not allowed. This is attempt $count and has '
                  'been recorded against your account.'
              : 'Screenshots of lesson content are not allowed. This has been '
                  'recorded against your account.',
        ),
      ),
    );
  }

  Future<void> _pause() async {
    try {
      await _controller?.runJavaScript(
        'try{document.querySelectorAll("video").forEach(v=>v.pause());}catch(e){}',
      );
    } catch (_) {
      // The page may not be loaded yet.
    }
    widget.onPlayingChanged?.call(false);
  }

  // ───────────────────────── watermark drift ─────────────────────────

  void _startWatermarkDrift() {
    // 20-30s, re-rolled each tick so the movement is not predictable.
    void schedule() {
      _watermarkTimer = Timer(
        Duration(seconds: 20 + _rng.nextInt(11)),
        () {
          if (!mounted) return;
          setState(() {
            _wmPrimary = _randomAlignment(top: true);
            _wmSecondary = _randomAlignment(top: false);
          });
          schedule();
        },
      );
    }

    schedule();
  }

  Alignment _randomAlignment({required bool top}) {
    // Keep it off the exact edge so it survives a light crop, and off centre
    // so it does not sit over the play button.
    final x = -0.75 + _rng.nextDouble() * 1.5;
    final y =
        top ? -0.85 + _rng.nextDouble() * 0.35 : 0.5 + _rng.nextDouble() * 0.35;
    return Alignment(x, y);
  }

  void _armTtl() {
    if (!widget.embed.provider.isSigned) return;
    // Re-fetch shortly before the signed URL dies rather than after, so the
    // student never sees the iframe refuse mid-lesson.
    _ttlTimer = Timer(ContentEmbed.signedTtl, () {
      if (mounted) widget.onExpired?.call();
    });
  }

  // ───────────────────────── navigation lockdown ─────────────────────────

  // Built from the URL actually loaded, not the raw embed, so the Bunny
  // share-disabling params do not make the player's own page look foreign to
  // its allowlist.
  late final _policy = PlayerNavigationPolicy(
      loadedUrl: SecureWebPlayer.playbackUrl(widget.embed));

  NavigationDecision _onNavigationRequest(NavigationRequest req) {
    final url = Uri.tryParse(req.url);
    if (url == null) return NavigationDecision.prevent;

    // Our own teardown. Allowed only while disposing, so `about:blank` stays
    // unreachable as an escape route during playback.
    if (_tearingDown && url.scheme == 'about') {
      return NavigationDecision.navigate;
    }

    final allow = _policy.isAllowed(url);
    if (!allow) {
      // A redirect to a sign-in host means the content is not shared publicly,
      // not that the network is down. Remember it so the error can say so.
      if (PlayerNavigationPolicy.isAuthWallHost(url.host)) {
        _blockedByAuthWall = true;
        if (mounted) setState(() => _failed = true);
      }
      // Log the host only — never the full URL, which for Bunny carries the
      // signed token.
      AppLogger.I.w('Player blocked navigation to ${url.scheme}://${url.host}');
    }
    return allow ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  // ───────────────────────── webview ─────────────────────────

  WebViewController _buildController() {
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        // Autoplay must work, so no gesture requirement.
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }

    final c = WebViewController.fromPlatformCreationParams(params);

    if (c.platform is AndroidWebViewController) {
      final android = c.platform as AndroidWebViewController;
      // The players need JS, but nothing may open a second window — that is
      // the other route a pop-out takes.
      android.setMediaPlaybackRequiresUserGesture(false);
      AndroidWebViewController.enableDebugging(false);
    }

    c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('LMP', onMessageReceived: _onBridgeMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageStarted: (_) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _failed = false;
            });
          },
          onPageFinished: (_) async {
            if (!mounted) return;
            setState(() => _loading = false);
            await _hardenPage();
          },
          onWebResourceError: (err) {
            if (!mounted) return;
            if (err.isForMainFrame ?? false) {
              setState(() {
                _loading = false;
                _failed = true;
              });
              widget.onError?.call();
            }
          },
        ),
      )
      ..loadRequest(_loaded);

    return c;
  }

  void _onBridgeMessage(JavaScriptMessage msg) {
    // Intentionally tolerant: the bridge is best-effort telemetry, and a
    // malformed message must never take the player down.
    try {
      final raw = msg.message;
      if (raw.startsWith('play')) {
        widget.onPlayingChanged?.call(true);
      } else if (raw.startsWith('pause') || raw.startsWith('ended')) {
        widget.onPlayingChanged?.call(false);
        if (raw.startsWith('ended')) widget.onEnded?.call();
      } else if (raw.startsWith('time:')) {
        final parts = raw.substring(5).split(',');
        final pos = int.tryParse(parts.first);
        final dur = parts.length > 1 ? int.tryParse(parts[1]) : null;
        if (pos != null) widget.onPositionChanged?.call(pos, dur);
      }
    } catch (_) {
      // Ignore.
    }
  }

  /// Injected hardening. Best-effort by design.
  ///
  /// Google's markup changes without notice, so every selector here is
  /// expected to go stale eventually. It is wrapped so it can only fail
  /// silently — the [AbsorbPointer] overlay and the navigation lockdown are
  /// what we actually depend on.
  Future<void> _hardenPage() async {
    const js = r'''
      (function(){
        try {
          if (window.__lmSecured) return; window.__lmSecured = true;

          // 1. Kill selection, the long-press callout and the context menu.
          var css = document.createElement('style');
          css.textContent =
            '*{-webkit-touch-callout:none!important;' +
            '-webkit-user-select:none!important;user-select:none!important;}' +
            // Drive's toolbar / pop-out chrome. These class names WILL rot.
            '.ndfHFb-c4YZDc-Wrql6b,.drive-viewer-toolstrip,' +
            '[data-tooltip="Open in new window"],[aria-label="Open in new window"],' +
            '[aria-label="Pop-out"],.goog-inline-block.punch-viewer-nav-button' +
            '{display:none!important;visibility:hidden!important;' +
            'pointer-events:none!important;}';
          document.documentElement.appendChild(css);

          document.oncontextmenu = function(e){ e.preventDefault(); return false; };
          document.addEventListener('contextmenu',
            function(e){ e.preventDefault(); }, true);
          document.addEventListener('dragstart',
            function(e){ e.preventDefault(); }, true);

          // 2. Re-apply after Drive re-renders its chrome.
          var strip = function(){
            try {
              var sels = ['[aria-label="Open in new window"]',
                          '[aria-label="Pop-out"]',
                          '.ndfHFb-c4YZDc-Wrql6b',
                          '.drive-viewer-toolstrip'];
              for (var i=0;i<sels.length;i++){
                var els = document.querySelectorAll(sels[i]);
                for (var j=0;j<els.length;j++){ els[j].remove(); }
              }
            } catch(e){}
          };
          strip();
          try {
            new MutationObserver(strip).observe(
              document.documentElement, {childList:true, subtree:true});
          } catch(e){}

          // 3. Playback telemetry.
          function post(m){ try { LMP.postMessage(m); } catch(e){} }
          function wire(v){
            if (!v || v.__lmWired) return; v.__lmWired = true;
            v.addEventListener('play',  function(){ post('play'); });
            v.addEventListener('pause', function(){ post('pause'); });
            v.addEventListener('ended', function(){ post('ended'); });
            v.addEventListener('timeupdate', function(){
              post('time:' + Math.floor(v.currentTime||0) + ',' +
                   Math.floor(v.duration||0));
            });
          }
          setInterval(function(){
            try { document.querySelectorAll('video').forEach(wire); } catch(e){}
          }, 1000);

          window.__lmSeek = function(s){
            try { document.querySelectorAll('video').forEach(
              function(v){ v.currentTime = s; }); } catch(e){}
          };
        } catch(e){ /* never throw into the page */ }
      })();
    ''';
    try {
      await _controller?.runJavaScript(js);
      if (widget.startAtSeconds > 5) {
        await _controller?.runJavaScript(
          'try{window.__lmSeek(${widget.startAtSeconds});}catch(e){}',
        );
      }
    } catch (_) {
      // Cross-origin frames refuse injection; the overlay still covers us.
    }
  }

  // ───────────────────────── build ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Re-measured on every layout, so the overlay tracks fullscreen and
        // rotation instead of drifting over the video.
        final stripHeight = math.max(44.0, constraints.maxHeight * 0.13);
        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (c != null && !_failed) WebViewWidget(controller: c),

              // Layer 2 of the pop-out defence: an opaque, non-interactive
              // strip over the region where Drive draws its controls. Taps
              // never reach the WebView. Independent of Google's DOM, so it
              // keeps working when the injected CSS goes stale.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: stripHeight,
                child: const AbsorbPointer(
                  child: ColoredBox(color: Colors.black),
                ),
              ),

              // The watermark sits above the strip so it is never occluded,
              // and inside the same Stack so it is present in fullscreen too.
              // A watermark that vanishes at the moment the screen is worth
              // recording is decoration.
              IgnorePointer(
                child: WatermarkLayer(
                  text: widget.watermark,
                  primary: _wmPrimary,
                  secondary: _wmSecondary,
                ),
              ),

              if (_loading)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white70),
                ),

              if (_failed) _PlayerError(authWall: _blockedByAuthWall),

              if (_blockedBy != null) CaptureBlockPanel(type: _blockedBy!),
            ],
          ),
        );
      },
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError({this.authWall = false});

  /// The load failed because the host tried to send us to a sign-in page,
  /// which the allowlist refused. That is a sharing-permission problem on the
  /// content, not a network problem, and telling the student to check their
  /// connection sends them chasing the wrong thing.
  final bool authWall;

  @override
  Widget build(BuildContext context) {
    final (icon, title, body) = authWall
        ? (
            Icons.lock_outline_rounded,
            'This video is not available',
            'It has not been shared for viewing. Please tell your teacher so '
                'they can fix the sharing settings.',
          )
        : (
            Icons.wifi_off_rounded,
            'This video could not be loaded.',
            'Check your connection and try again.',
          );
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: Colors.white70, size: 36),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
              const SizedBox(height: 4),
              Text(
                body,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The navigation allowlist. **This is what kills the pop-out button.**
///
/// Drive's "open in new window" control works by navigating. Deny the
/// navigation and the button does nothing at all, whatever it looks like —
/// which is why hiding it is treated here as cosmetic rather than as the
/// defence.
///
/// Extracted from the widget so the policy can be tested exhaustively without
/// a WebView: every escape route someone might tap is a test case, and a
/// regression here is invisible in a screenshot.
class PlayerNavigationPolicy {
  const PlayerNavigationPolicy({required this.loadedUrl});

  /// The exact URL the player was told to load. Always permitted.
  final String loadedUrl;

  /// Hosts the players legitimately fetch assets and media from.
  static const allowedHostSuffixes = <String>{
    // Bunny Stream
    'mediadelivery.net',
    'b-cdn.net',
    'bunnycdn.com',
    // Cloudflare Stream
    'videodelivery.net',
    'cloudflarestream.com',
    // Google Drive preview and the media it pulls
    'drive.google.com',
    'googleusercontent.com',
    'googlevideo.com',
    'gstatic.com',
    'googleapis.com',
    'youtube.com',
    'ytimg.com',
  };

  /// Schemes that must never be handed to the OS.
  ///
  /// `intent://` and `market://` are how an Android WebView is talked into
  /// opening another app; the rest are share/compose targets.
  static const blockedSchemes = <String>{
    'intent',
    'market',
    'mailto',
    'tel',
    'sms',
    'geo',
    'file',
    'content',
    'itms-apps',
    'itms-appss',
    'whatsapp',
    'fb',
    'twitter',
    'about',
    'javascript',
    'data',
    'blob',
    'http',
  };

  /// Hosts that mean "this content wants you to sign in", which for an
  /// embedded player means the file is not publicly viewable.
  static bool isAuthWallHost(String host) {
    final h = host.toLowerCase();
    return h == 'accounts.google.com' ||
        h.endsWith('.accounts.google.com') ||
        h == 'accounts.youtube.com';
  }

  bool isAllowed(Uri url) {
    final scheme = url.scheme.toLowerCase();

    // Everything is HTTPS. `http` is in the blocked set deliberately: a
    // downgrade is either a misconfiguration or an attack.
    if (scheme != 'https') return false;
    if (blockedSchemes.contains(scheme)) return false;

    // The exact page we loaded is always fine.
    if (url.toString() == loadedUrl) return true;

    final host = url.host.toLowerCase();
    final allowed = allowedHostSuffixes.any(
      (s) => host == s || host.endsWith('.$s'),
    );
    if (!allowed) return false;

    // Drive is special: only the preview surface is permitted. `/view`,
    // `/edit`, `/open`, the file picker and the account chooser are all ways
    // out of the player and into a page with a share button on it.
    if (host == 'drive.google.com' || host.endsWith('.drive.google.com')) {
      return url.path.endsWith('/preview');
    }
    return true;
  }
}
