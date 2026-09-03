import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_application/secure_application.dart';

import '../core/design/app_theme.dart';
import '../core/error/failures.dart';
import '../features/announcements/announcements_screen.dart';
import '../features/assignments/assignment_detail_screen.dart';
import '../features/assignments/assignments_screen.dart';
import '../features/auth/presentation/auth_controller.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/register_screen.dart';
import '../features/auth/presentation/splash_screen.dart';
import '../features/content_player/content_player_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/notifications/push_service.dart';
import '../features/parent/parent_home_screen.dart';
import '../features/sync/realtime_poll_service.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/complete_profile_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/subjects/subject_detail_screen.dart';
import '../features/subjects/subjects_screen.dart';
import '../features/videos/class_videos_screen.dart';
import 'app_shell.dart';

class LoayMohamedApp extends ConsumerStatefulWidget {
  const LoayMohamedApp({super.key});
  @override
  ConsumerState<LoayMohamedApp> createState() => _LoayMohamedAppState();
}

class _LoayMohamedAppState extends ConsumerState<LoayMohamedApp> {
  bool _splashElapsed = false;

  @override
  void initState() {
    super.initState();
    // Keep the splash on screen for at least 2s for branding.
    Future<void>.delayed(const Duration(seconds: 2)).then((_) {
      if (mounted) setState(() => _splashElapsed = true);
    });
    // Bootstrap auth on app start.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(authControllerProvider.notifier).bootstrap();
      // Activate push side-effect listener.
      ref.read(pushBootstrapProvider);
      // Activate realtime polling fallback (covers cases where push isn't
      // delivered, e.g. iOS simulator or denied permission).
      ref.read(realtimePollBootstrapProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final navKey = ref.read(rootNavigatorKeyProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Central logout handler — whenever auth transitions FROM authenticated (or
    // unknown) TO unauthenticated, push to /login and clear the entire stack.
    // This is the single source of truth for post-logout navigation so that
    // individual screens don't need their own navigation calls.
    ref.listen<AuthState>(authControllerProvider, (prev, next) {
      // ─── unauthenticated → authenticated (login / social sign-in) ───────
      // The MaterialApp.home: property has already rebuilt to the correct
      // post-auth screen (AppShell / ParentHomeScreen / CompleteProfile),
      // but it sits UNDER any routes we pushed while logged-out (e.g. the
      // pushed /login route after a previous logout). Pop everything down
      // to the root route to reveal it.
      if (next.status == AuthStatus.authenticated &&
          prev?.status != AuthStatus.authenticated) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navKey.currentState?.popUntil((r) => r.isFirst);
        });
        return;
      }

      if (next.status != AuthStatus.unauthenticated) return;
      // Only fire when we were previously in a non-unauthenticated state to
      // avoid re-navigating on every build while already on the login screen.
      if (prev?.status == AuthStatus.unauthenticated) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navKey.currentContext;
        if (ctx == null) return;

        // Show an explanatory message for server-driven logouts.
        final err = next.error;
        if (err is AccountBlockedFailure) {
          showDialog<void>(
            context: ctx,
            barrierDismissible: false,
            builder: (dialogCtx) => AlertDialog(
              icon: Icon(Icons.block_rounded,
                  color: Theme.of(dialogCtx).colorScheme.error, size: 36),
              title: const Text('Account blocked'),
              content: Text(err.message),
              actions: [
                FilledButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        } else if (err is SessionRevokedFailure) {
          ScaffoldMessenger.maybeOf(ctx)
              ?.showSnackBar(SnackBar(content: Text(err.message)));
        }

        // Always navigate to /login and clear the stack, regardless of the
        // reason for logout (manual, token expiry, server revoke, blocked).
        Navigator.of(ctx)
            .pushNamedAndRemoveUntil('/login', (_) => false);
      });
    });

    final Widget home;
    if (auth.status == AuthStatus.unknown || !_splashElapsed) {
      home = const SplashScreen();
    } else if (auth.status == AuthStatus.authenticated) {
      final user = auth.user;
      // Parents go to their own home screen.
      if (user != null && user.isParent) {
        home = const ParentHomeScreen();
      } else if (user != null && !user.isProfileComplete) {
        home = const CompleteProfileScreen();
      } else {
        home = const AppShell();
      }
    } else {
      home = const LoginScreen();
    }

    return MaterialApp(
      navigatorKey: navKey,
      title: 'Loay Mohamed E-Learning',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      builder: (context, child) => SecureApplication(
        nativeRemoveDelay: 0,
        autoUnlockNative: true,
        secureApplicationController: SecureApplicationController(
          // Start in secured mode so Android FLAG_SECURE is on for the entire
          // app lifetime (blocks screenshots & screen recording).
          SecureApplicationState(secured: true, authenticated: true),
        ),
        child: SecureGate(
          blurr: 60,
          opacity: 1.0,
          lockedBuilder: (context, controller) => const ColoredBox(
            color: Colors.black,
            child: SizedBox.expand(),
          ),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
      home: home,
      onGenerateRoute: (settings) {
        final name = settings.name ?? '/';
        // Subject detail: /subjects/:id
        if (name.startsWith('/subjects/') &&
            name.length > '/subjects/'.length) {
          final id = name.substring('/subjects/'.length);
          return MaterialPageRoute(
              builder: (_) => SubjectDetailScreen(subjectId: id),
              settings: settings,);
        }
        // Assignment detail: /assignments/:id
        if (name.startsWith('/assignments/') &&
            name.length > '/assignments/'.length) {
          final id = name.substring('/assignments/'.length);
          return MaterialPageRoute(
              builder: (_) => AssignmentDetailScreen(id: id),
              settings: settings,);
        }
        // Class videos (Cloudflare Stream): /classes/:id/videos
        // Optional `?group=<title>` query string deep-links to a specific
        // lesson group inside the list.
        if (name.startsWith('/classes/') && name.contains('/videos')) {
          final uri = Uri.parse(name);
          final segments = uri.pathSegments;
          if (segments.length >= 3 &&
              segments[0] == 'classes' &&
              segments[2] == 'videos') {
            final classId = segments[1];
            final group = uri.queryParameters['group'];
            return MaterialPageRoute(
              builder: (_) => ClassVideosScreen(
                classId: classId,
                highlightGroup: group,
              ),
              settings: settings,
            );
          }
        }
        switch (name) {
          case '/parent/home':
            return MaterialPageRoute(
                builder: (_) => const ParentHomeScreen(),
                settings: settings);
          case '/home':
            return MaterialPageRoute(
                builder: (_) => const AppShell(), settings: settings);
          case '/login':
            return MaterialPageRoute(
                builder: (_) => const LoginScreen(), settings: settings,);
          case '/register':
            return MaterialPageRoute(
                builder: (_) => const RegisterScreen(), settings: settings,);
          case '/subjects':
            return MaterialPageRoute(
                builder: (_) => const SubjectsScreen(), settings: settings,);
          case '/assignments':
            return MaterialPageRoute(
                builder: (_) => const AssignmentsScreen(), settings: settings,);
          case '/quizzes':
            return MaterialPageRoute(
              builder: (_) => const AssignmentsScreen(type: 'quiz'),
              settings: settings,
            );
          case '/announcements':
            return MaterialPageRoute(
                builder: (_) => const AnnouncementsScreen(),
                settings: settings,);
          case '/notifications':
            return MaterialPageRoute(
                builder: (_) => const NotificationsScreen(),
                settings: settings,);
          case '/profile':
            return MaterialPageRoute(
                builder: (_) => const ProfileScreen(), settings: settings,);
          case '/complete-profile':
            return MaterialPageRoute(
                builder: (_) => const CompleteProfileScreen(),
                settings: settings,);
          case '/settings':
            return MaterialPageRoute(
                builder: (_) => const SettingsScreen(), settings: settings,);
          case '/player':
            final args = settings.arguments as Map?;
            if (args == null) return null;
            return MaterialPageRoute(
              builder: (_) => ContentPlayerScreen(
                contentId: args['contentId'].toString(),
                lessonId: args['lessonId']?.toString(),
                subjectId: args['subjectId'].toString(),
                title: args['title']?.toString(),
              ),
              settings: settings,
            );
          default:
            return null;
        }
      },
    );
  }
}
