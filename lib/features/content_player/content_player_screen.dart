import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_application/secure_application.dart';
import 'package:webview_flutter/webview_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_android/webview_flutter_android.dart';
// ignore: depend_on_referenced_packages
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../core/error/failures.dart';
import '../../core/providers.dart';
import '../../core/storage/kv_cache.dart';
import '../auth/presentation/auth_controller.dart';
import '../providers.dart';
import '../student_repository.dart';

/// Plays remote video via the secure embed URL.
/// - Uses the embed's own player UI (best UX with cross-origin iframes).
/// - Minimal Flutter chrome: back, fullscreen, watermark.
/// - Auto-rotates to landscape, restores on exit.
/// - Screenshot/recording protection via SecureApplication (Android FLAG_SECURE)
///   plus a user watermark to deter sharing on iOS where blocking isn't possible.
class ContentPlayerScreen extends ConsumerStatefulWidget {
  const ContentPlayerScreen({
    super.key,
    required this.contentId,
    required this.subjectId,
    this.lessonId,
    this.title,
  });

  final String contentId;
  final String subjectId;
  final String? lessonId;
  final String? title;

  @override
  ConsumerState<ContentPlayerScreen> createState() =>
      _ContentPlayerScreenState();
}

class _ContentPlayerScreenState extends ConsumerState<ContentPlayerScreen>
    with WidgetsBindingObserver {
  WebViewController? _web;

  bool _pageLoading = true;
  bool _hasError = false;
  bool _fullscreen = false;
  Timer? _showChromeTimer;
  bool _chromeVisible = true;

  // ── Resume / heartbeat state ─────────────────────────────────────────────
  int _positionSeconds = 0;
  int _durationSeconds = 0;
  Timer? _heartbeatTimer;
  bool _resumeApplied = false;
  // Watched-time tracking: backend wants `delta = seconds watched since last
  // heartbeat` (clamped 0–60), not a position delta.
  bool _playing = false;
  DateTime _lastTick = DateTime.now();
  // Playhead position at the previous heartbeat. We derive watched `delta`
  // from how far the playhead actually advanced — this is robust even when
  // the embed's play/pause events never reach us (the `timeupdate` events
  // still do), so the backend keeps advancing the resume point.
  int _lastHeartbeatPosition = 0;

  // Cached repository so dispose-time flushes don't touch `ref` after the
  // widget has been unmounted (Riverpod throws if you do).
  StudentRepository? _repo;

  // Local resume cache. The backend resume point isn't always reliable, so we
  // also persist the last position on-device keyed by user + content. This
  // guarantees resume works on the same device for the same user, while
  // staying per-user isolated (User B never inherits User A's position).
  KvCache? _kv;
  String? _resumeKey;

  String? _buildResumeKey() {
    final uid = ref.read(authControllerProvider).user?.id ?? 'anon';
    return 'resume.$uid.${widget.contentId}';
  }

  void _saveLocalResume(int seconds) {
    final kv = _kv;
    final key = _resumeKey;
    if (kv == null || key == null || seconds <= 0) return;
    // Don't persist a position essentially at the start.
    if (seconds <= 3) return;
    kv.setInt(key, seconds);
  }

  int _readLocalResume() {
    final kv = _kv;
    final key = _resumeKey;
    if (kv == null || key == null) return 0;
    return kv.getInt(key) ?? 0;
  }

  @override
  void initState() {
    super.initState();
    // Cache the repository immediately so dispose() can still flush the
    // final position even after the ConsumerElement has been torn down.
    _repo = ref.read(studentRepositoryProvider);
    _kv = ref.read(kvCacheProvider);
    _resumeKey = _buildResumeKey();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _enableProtection());
    _scheduleChromeHide();
    // Mark as seen the moment the player opens — we don't track minutes.
    WidgetsBinding.instance.addPostFrameCallback((_) => _markSeen());
    // Periodic upload of current position to backend (every 15s, per spec).
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _sendHeartbeat(),
    );
  }

  Future<void> _markSeen() async {
    final StudentRepository repo =
        _repo ?? ref.read(studentRepositoryProvider);
    _repo ??= repo;
    try {
      // A 1-second heartbeat is enough for the backend to flag this content
      // as watched. We don't actually care about minute totals.
      await repo.sendHeartbeat(
        contentId: widget.contentId,
        classOrSubjectId: widget.subjectId,
        deltaSeconds: 1,
        currentPositionSeconds: 1,
        tabVisible: true,
      );
      // Refresh providers so the "Videos seen" counters update everywhere.
      if (mounted) {
        ref.invalidate(contentsProvider);
        ref.invalidate(contentProvider(widget.contentId));
        ref.invalidate(dashboardProvider);
        ref.invalidate(subjectWorkloadProvider);
      }
    } catch (_) {
      // Best-effort — next heartbeat tick will retry.
    }
  }

  @override
  void dispose() {
    // Persist the last position locally + flush to backend so the next
    // session (even after a full app restart) can resume.
    _saveLocalResume(_positionSeconds);
    _sendHeartbeat(force: true);
    _heartbeatTimer?.cancel();
    // Stop any audio/video that may still be playing inside the WebView.
    // Cross-origin iframes won't let us reach their <video>, so we also
    // navigate the WebView itself to `about:blank` which tears the page
    // (and the embedded player) down completely.
    final web = _web;
    if (web != null) {
      // Best-effort JS pause for same-origin media.
      web.runJavaScript(
        "document.querySelectorAll('video,audio').forEach(function(m){"
        "  try{m.pause(); m.muted=true; m.src=''; m.load();}catch(e){}"
        "});",
      ).catchError((_) {});
      web.loadRequest(Uri.parse('about:blank')).catchError((_) {});
    }
    _web = null;
    WidgetsBinding.instance.removeObserver(this);
    _showChromeTimer?.cancel();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveLocalResume(_positionSeconds);
      _sendHeartbeat(force: true);
    }
  }

  Future<void> _sendHeartbeat({bool force = false}) async {
    // Backend semantics: `delta` = seconds **watched** since the last
    // heartbeat (clamped 0–60). We derive it from how far the playhead
    // actually advanced rather than relying on the embed's play/pause
    // events (which don't always reach us). The `timeupdate` position events
    // do arrive, so position-advance is the reliable signal that the user is
    // genuinely watching — and it keeps the backend's resume point moving.
    final now = DateTime.now();
    final wall = now.difference(_lastTick).inSeconds.clamp(0, 60);
    _lastTick = now;
    final advanced = _positionSeconds - _lastHeartbeatPosition;
    int delta;
    if (advanced > 0) {
      // Normal forward playback (or a forward seek). Count the seconds the
      // playhead moved, capped at 60 so a big jump can't inflate watch time.
      delta = advanced.clamp(0, 60);
    } else if ((_playing || force) && advanced == 0 && _positionSeconds > 0) {
      // Playhead didn't report movement but we believe we're playing — fall
      // back to wall-clock so a stalled `timeupdate` doesn't zero out watch
      // time.
      delta = wall;
    } else {
      // Paused, seeked backward, or not started: no watched time.
      delta = 0;
    }
    _lastHeartbeatPosition = _positionSeconds;
    if (!force && delta == 0 && _positionSeconds <= 0) return;
    // Use cached repo if available (e.g. during dispose) — `ref.read` throws
    // once the ConsumerStatefulElement has been disposed.
    final repo = _repo;
    if (repo == null) return;
    try {
      await repo.sendHeartbeat(
        contentId: widget.contentId,
        classOrSubjectId: widget.subjectId,
        deltaSeconds: delta,
        currentPositionSeconds: _positionSeconds,
        tabVisible: !force,
      );
    } catch (_) {
      // Silent — next tick will retry.
    }
  }

  void _enableProtection() {
    final c = SecureApplicationProvider.of(context, listen: false);
    c?.secure();
  }

  void _scheduleChromeHide() {
    _showChromeTimer?.cancel();
    // Give the user enough time to find the exit button.
    _showChromeTimer = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _chromeVisible = false);
    });
  }

  void _toggleChrome() {
    setState(() => _chromeVisible = !_chromeVisible);
    if (_chromeVisible) _scheduleChromeHide();
  }

  Future<void> _enterFullscreen() async {
    setState(() => _fullscreen = true);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _chromeVisible = true);
    _scheduleChromeHide();
  }

  Future<void> _exitFullscreen() async {
    await _sendHeartbeat(force: true);
    setState(() => _fullscreen = false);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() => _chromeVisible = true);
    _scheduleChromeHide();
  }

  Future<void> _reload() async {
    setState(() {
      _pageLoading = true;
      _hasError = false;
    });
    await _web?.reload();
  }

  // ── Build webview ────────────────────────────────────────────────────────
  /// Forces the embedded player UI to English regardless of device locale, so
  /// captions/menus don't render in Arabic on Arabic-localized devices.
  String _ensureEnglishUrl(String url) {
    if (url.isEmpty) return url;
    final hasQ = url.contains('?');
    final sep = hasQ ? '&' : '?';
    final extras = <String>[];
    if (!url.contains('texttrack=')) extras.add('texttrack=en');
    if (!url.contains('hl=')) extras.add('hl=en');
    if (!url.contains('cc_lang_pref=')) extras.add('cc_lang_pref=en');
    if (extras.isEmpty) return url;
    return '$url$sep${extras.join('&')}';
  }

  WebViewController _buildWebView(String url, {int startAt = 0}) {
    var finalUrl = _ensureEnglishUrl(url);
    if (startAt > 5) {
      // Bonus for embeds where the URL *is* the direct player iframe. For
      // page-hosted cross-origin iframes this param is ignored, so the JS
      // seek in `_applyResumeIfNeeded` remains the authoritative resume.
      final sep = finalUrl.contains('?') ? '&' : '?';
      finalUrl = '$finalUrl${sep}startTime=${startAt}s&autoplay=true';
    }
    late final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }
    final c = WebViewController.fromPlatformCreationParams(params);
    if (c.platform is AndroidWebViewController) {
      (c.platform as AndroidWebViewController)
          .setMediaPlaybackRequiresUserGesture(false);
    }
    c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        'LMP',
        onMessageReceived: (msg) {
          try {
            final m = jsonDecode(msg.message) as Map<String, dynamic>;
            final type = m['t']?.toString() ?? '';
            switch (type) {
              case 'play':
                _playing = true;
                _lastTick = DateTime.now();
                break;
              case 'pause':
              case 'ended':
                _playing = false;
                _sendHeartbeat(force: true);
                break;
              case 'time':
                final pos = (m['s'] as num?)?.toInt();
                final dur = (m['d'] as num?)?.toInt();
                if (pos != null && pos > 0) {
                  _positionSeconds = pos;
                  _saveLocalResume(pos);
                }
                if (dur != null && dur > 0) _durationSeconds = dur;
                break;
              default:
                // Legacy {position, duration} payload from the old bridge.
                final pos = (m['position'] as num?)?.toInt();
                final dur = (m['duration'] as num?)?.toInt();
                if (pos != null && pos > 0) {
                  _positionSeconds = pos;
                  _saveLocalResume(pos);
                }
                if (dur != null && dur > 0) _durationSeconds = dur;
            }
          } catch (_) {/* ignore */}
        },
      )
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) {
          if (!mounted) return;
          setState(() {
            _pageLoading = true;
            _hasError = false;
          });
        },
        onPageFinished: (_) async {
          if (!mounted) return;
          setState(() => _pageLoading = false);
          await _injectPlayerBridge(c);
          await _applyResumeIfNeeded(c);
        },
        onWebResourceError: (err) {
          if (!mounted) return;
          if (err.isForMainFrame ?? false) {
            setState(() {
              _pageLoading = false;
              _hasError = true;
            });
          }
        },
      ),)
      ..loadRequest(Uri.parse(finalUrl));
    return c;
  }

  /// Injects a small JS bridge that:
  ///   • Loads the Cloudflare Stream Player SDK and subscribes to
  ///     play/pause/timeupdate so we can drive watch-heartbeats from real
  ///     playback events (not just wall-clock time).
  ///   • Falls back to direct <video>/Vimeo postMessage for non-Stream embeds.
  ///   • Exposes `window.__lmpSeek(seconds)` for resume.
  ///   • Posts typed events back to Flutter via the `LMP` channel:
  ///       {t:'play'} | {t:'pause'} | {t:'ended'} | {t:'time', s, d}
  Future<void> _injectPlayerBridge(WebViewController c) async {
    await c.runJavaScript(r'''
      (function(){
        if (window.__lmpInstalled) return; window.__lmpInstalled = true;
        function post(o){ try { LMP.postMessage(JSON.stringify(o)); } catch(e){} }

        // Stretch player full-bleed.
        try {
          var s = document.createElement('style');
          s.textContent = 'body{margin:0;background:#000} html,body{height:100%} iframe,video{width:100%!important;height:100%!important;border:0;background:#000}';
          (document.head||document.documentElement).appendChild(s);
        } catch(e){}

        // Try to autoplay direct <video> tags.
        try {
          document.querySelectorAll('video').forEach(function(v){
            v.muted = true;
            v.setAttribute('playsinline','');
            v.setAttribute('webkit-playsinline','');
            var p = v.play && v.play(); if (p && p.catch) p.catch(function(){});
          });
        } catch(e){}

        // ---- Cloudflare Stream Player SDK ---------------------------------
        function attachStream(){
          if (!window.Stream) return;
          var ifr = document.querySelector('iframe');
          if (!ifr) return;
          try {
            var sp = window.Stream(ifr);
            sp.addEventListener('play',  function(){ post({t:'play'}); });
            sp.addEventListener('pause', function(){ post({t:'pause'}); });
            sp.addEventListener('ended', function(){ post({t:'ended'}); });
            sp.addEventListener('timeupdate', function(){
              var s = 0, d = 0;
              try { s = Math.floor(sp.currentTime||0); } catch(e){}
              try { d = Math.floor(sp.duration||0); } catch(e){}
              post({t:'time', s:s, d:d});
            });
            window.__lmpStream = sp;
            // Apply a pending resume seek as soon as the player is ready.
            // Cross-origin iframe playback can only be seeked through the SDK,
            // and only once metadata has loaded — so we hook both events and
            // also retry a few times.
            sp.addEventListener('loadedmetadata', function(){ window.__lmpApplySeek(); });
            sp.addEventListener('canplay', function(){ window.__lmpApplySeek(); });
            window.__lmpApplySeek();
          } catch(e){}
        }
        if (!window.Stream){
          var sk = document.createElement('script');
          sk.src = 'https://embed.videodelivery.net/embed/sdk.latest.js';
          sk.onload = attachStream;
          (document.head||document.documentElement).appendChild(sk);
        } else { attachStream(); }

        // ---- Vimeo iframe fallback ---------------------------------------
        function vimeoFrame(){
          var fs = document.querySelectorAll('iframe');
          for (var i=0;i<fs.length;i++){
            var src = fs[i].src || '';
            if (/player\.vimeo\.com|vimeo\.com\/video/.test(src)) return fs[i];
          }
          return null;
        }
        var vf = vimeoFrame();
        function vpost(m){ if (vf && vf.contentWindow) try{ vf.contentWindow.postMessage(JSON.stringify(m), '*'); }catch(e){} }
        if (vf){
          vpost({method:'addEventListener', value:'timeupdate'});
          vpost({method:'addEventListener', value:'play'});
          vpost({method:'addEventListener', value:'pause'});
          vpost({method:'addEventListener', value:'ended'});
          vpost({method:'getDuration'});
          vpost({method:'play'});
        }

        var lastPos = 0, lastDur = 0;
        // Desired resume position. We keep retrying until the player's
        // currentTime actually lands near the target, because cross-origin
        // Stream players ignore seeks issued before metadata is ready.
        window.__lmpSeekTarget = window.__lmpSeekTarget || 0;
        window.__lmpSeekTries = 0;
        window.__lmpApplySeek = function(){
          var sec = window.__lmpSeekTarget || 0;
          if (sec <= 0) return;
          try { document.querySelectorAll('video').forEach(function(v){ try { v.currentTime = sec; var p=v.play(); if(p&&p.catch)p.catch(function(){}); } catch(e){} }); } catch(e){}
          if (vf) vpost({method:'setCurrentTime', value: sec});
          if (window.__lmpStream) {
            try {
              window.__lmpStream.currentTime = sec;
              var p2 = window.__lmpStream.play && window.__lmpStream.play();
              if (p2 && p2.catch) p2.catch(function(){});
            } catch(e){}
          }
        };
        window.__lmpSeek = function(sec){
          window.__lmpSeekTarget = sec;
          window.__lmpSeekTries = 0;
          window.__lmpApplySeek();
          // Retry for a few seconds: the player may not have loaded metadata
          // yet, and the first few seeks are silently dropped.
          var iv = setInterval(function(){
            window.__lmpSeekTries++;
            var cur = 0;
            try { cur = Math.floor((window.__lmpStream && window.__lmpStream.currentTime) || (document.querySelector('video')||{}).currentTime || 0); } catch(e){}
            if (cur >= sec - 3 || window.__lmpSeekTries > 20) { clearInterval(iv); return; }
            window.__lmpApplySeek();
          }, 500);
        };

        function sendDirect(){
          try {
            var v = document.querySelector('video');
            if (v && isFinite(v.currentTime)) {
              lastPos = Math.floor(v.currentTime);
              if (isFinite(v.duration)) lastDur = Math.floor(v.duration);
              post({t:'time', s:lastPos, d:lastDur});
            }
          } catch(e){}
        }

        window.addEventListener('message', function(ev){
          var d = ev.data;
          if (typeof d === 'string'){ try { d = JSON.parse(d); } catch(e){ return; } }
          if (!d) return;
          if (d.event === 'play')   post({t:'play'});
          if (d.event === 'pause')  post({t:'pause'});
          if (d.event === 'ended')  post({t:'ended'});
          if (d.event === 'timeupdate' && d.data){
            if (typeof d.data.seconds === 'number') lastPos = Math.floor(d.data.seconds);
            if (typeof d.data.duration === 'number') lastDur = Math.floor(d.data.duration);
            post({t:'time', s:lastPos, d:lastDur});
          } else if (d.method === 'getDuration' && typeof d.value === 'number'){
            lastDur = Math.floor(d.value);
          }
        });

        setInterval(sendDirect, 1000);

        // Try unmute shortly after.
        setTimeout(function(){
          try { document.querySelectorAll('video').forEach(function(v){ v.muted=false; }); } catch(e){}
        }, 800);
      })();
    ''');
  }

  Future<void> _applyResumeIfNeeded(WebViewController c) async {
    if (_resumeApplied) return;
    try {
      int sec = _readLocalResume();
      try {
        final resume =
            await ref.read(contentResumeProvider(widget.contentId).future);
        sec = math.max(sec, resume.resumeFromSeconds);
      } catch (_) {
        // Backend resume unavailable — fall back to the local value.
      }
      if (sec > 3) {
        _resumeApplied = true;
        _positionSeconds = sec;
        _lastHeartbeatPosition = sec;
        // Wait briefly for the player to mount before seeking.
        await Future<void>.delayed(const Duration(milliseconds: 1200));
        await c.runJavaScript('window.__lmpSeek && window.__lmpSeek($sec);');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Resumed at ${_fmt(sec)}'),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      } else {
        _resumeApplied = true;
      }
    } catch (_) {
      _resumeApplied = true; // Don't keep retrying on failure.
    }
  }

  static String _fmt(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '${two(h)}:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final embed = ref.watch(contentEmbedProvider(widget.contentId));
    final user = ref.watch(authControllerProvider).user;
    final orientation = MediaQuery.of(context).orientation;
    // Sync internal _fullscreen flag with real orientation.
    final isLandscape = orientation == Orientation.landscape;
    if (isLandscape != _fullscreen) {
      // Don't call setState during build — schedule a microtask.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_fullscreen != isLandscape) {
          setState(() => _fullscreen = isLandscape);
        }
      });
    }

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          top: !_fullscreen,
          // Respect the bottom inset in portrait so the embedded player's
          // timeline / play / fullscreen controls don't sit under the home
          // indicator. In fullscreen we want true full-bleed video.
          bottom: !_fullscreen,
          child: embed.when(
            loading: () => const _Loading(),
            error: (e, _) => _ErrorView(
              message: e is AppFailure ? e.message : e.toString(),
              onRetry: () =>
                  ref.invalidate(contentEmbedProvider(widget.contentId)),
            ),
            data: (data) {
              if (data.embedUrl.isEmpty) {
                return const _ErrorView(
                    message: 'Video unavailable for this lesson.',);
              }
              // Pre-fetch the resume position so we can hand it to Cloudflare
              // Stream via `?startTime=Ns&autoplay=true` (more reliable than
              // post-load JS seek).
              final resume =
                  ref.watch(contentResumeProvider(widget.contentId)).valueOrNull;
              final backendResume = resume?.resumeFromSeconds ?? 0;
              // Prefer whichever source has progressed further. The local
              // value covers cases where the backend hasn't persisted the
              // position yet.
              final resumeFrom = math.max(backendResume, _readLocalResume());
              _web ??= _buildWebView(data.embedUrl, startAt: resumeFrom);
              // Brand watermark + per-user identifier to deter sharing.
              final identity = user?.email ?? user?.name ?? '';
              final wm = identity.isEmpty
                  ? 'Loay Mohamed'
                  : 'Loay Mohamed · $identity';
              return _stage(wm);
            },
          ),
        ),
      ),
    );
  }

  Widget _stage(String watermarkLabel) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleChrome,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Player
          ColoredBox(
            color: Colors.black,
            child: _web == null
                ? const SizedBox.shrink()
                : WebViewWidget(controller: _web!),
          ),

          // Loading overlay
          if (_pageLoading) const _Loading(),

          // Error overlay
          if (_hasError)
            _ErrorView(
              message: 'Could not load the video. Please try again.',
              onRetry: _reload,
            ),

          // Watermark — visible at all times, subtle.
          IgnorePointer(
            child: _Watermark(label: watermarkLabel),
          ),

          // Persistent close/back button (never auto-hides) so the user can
          // always exit the player even when the chrome has faded out.
          Positioned(
            top: 12,
            left: 12,
            child: SafeArea(
              child: _RoundIcon(
                icon: _fullscreen
                    ? Icons.close_rounded
                    : Icons.arrow_back_ios_new_rounded,
                onTap: () async {
                  if (_fullscreen) {
                    await _exitFullscreen();
                  } else {
                    await _sendHeartbeat(force: true);
                    if (mounted) {
                      Navigator.of(context).maybePop();
                    }
                  }
                },
              ),
            ),
          ),

          // Top + bottom chrome (auto-hides).
          AnimatedOpacity(
            opacity: _chromeVisible ? 1 : 0,
            duration: const Duration(milliseconds: 220),
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: Stack(
                children: [
                  // Top bar
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                      child: Row(
                        children: [
                          // Spacer matching the persistent close button so the
                          // title doesn't collide with it.
                          const SizedBox(width: 44),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.title ?? 'Lesson',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (_positionSeconds > 0) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4,),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.45),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                _durationSeconds > 0
                                    ? '${_fmt(_positionSeconds)} / ${_fmt(_durationSeconds)}'
                                    : _fmt(_positionSeconds),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          _RoundIcon(
                            icon: Icons.refresh_rounded,
                            onTap: _reload,
                          ),
                          const SizedBox(width: 6),
                          _RoundIcon(
                            icon: _fullscreen
                                ? Icons.fullscreen_exit_rounded
                                : Icons.fullscreen_rounded,
                            onTap: _fullscreen
                                ? _exitFullscreen
                                : _enterFullscreen,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 38,
            height: 38,
            child: CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 2.4,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Loading video…',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.videocam_off_rounded,
              color: Colors.white54, size: 48,),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ),
    );
  }
}

/// Subtle, repeating user watermark. Helps trace shared screenshots/recordings.
class _Watermark extends StatelessWidget {
  const _Watermark({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (_, c) {
        const tileW = 220.0;
        const tileH = 140.0;
        final cols = (c.maxWidth / tileW).ceil() + 1;
        final rows = (c.maxHeight / tileH).ceil() + 1;
        return SizedBox.expand(
          child: Stack(
            children: [
              for (var r = 0; r < rows; r++)
                for (var col = 0; col < cols; col++)
                  Positioned(
                    left: col * tileW - (r.isOdd ? tileW / 2 : 0),
                    top: r * tileH,
                    child: Transform.rotate(
                      angle: -math.pi / 9,
                      child: Opacity(
                        opacity: 0.10,
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}
