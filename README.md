# Loay Mohamed E-Learning — Student Mobile App

A production-grade Flutter mobile app for students of Loay Mohamed E-Learning.
Clean architecture, Riverpod, Dio, OneSignal push, secure auth with refresh
rotation, full feature parity with the web student portal.

## Features

- Splash + branded login (with remember-me)
- Student Dashboard (KPIs + subjects with progress)
- Subjects list, subject detail, enrollment requests + status
- Lessons + Content player with secure embed, resume, and 15s heartbeat
- Watch-event tracking (`watch-events` + legacy `watch-heartbeat`)
- Per-subject progress (completion, watched seconds)
- Assignments + Quizzes (filter, detail, file/text submission, resubmit until graded)
- Announcements feed (global)
- Notifications inbox with mark one / mark all read
- Profile basics + change password + change phone
- Settings: theme mode (light/dark/system), push toggle
- OneSignal push: pre-prompt, external user id, device registration, deep linking

## Stack

- Flutter 3.19+ / Dart 3.3+
- State: `flutter_riverpod`
- HTTP: `dio` + `pretty_dio_logger` + custom auth/retry interceptors
- Secure storage: `flutter_secure_storage` (tokens), `shared_preferences` (cache)
- Push: `onesignal_flutter`
- Video: `webview_flutter` for secure embed playback
- Files: `file_picker`
- UI: `google_fonts` (Poppins + Montserrat), `shimmer`, `flutter_animate`

## Getting Started

```bash
flutter pub get

# Run dev flavor
flutter run -t lib/main_dev.dart

# Run staging
flutter run -t lib/main_staging.dart

# Build prod release
flutter build apk --release -t lib/main_prod.dart
flutter build ipa --release -t lib/main_prod.dart
```

### Environment configuration

Edit the `.env` files under `assets/env/`:

| Key                    | Purpose                                |
| ---------------------- | -------------------------------------- |
| `API_BASE_URL`         | Backend host (no trailing slash)       |
| `API_V1_PREFIX`        | Mobile-first v1 namespace              |
| `LEGACY_STUDENT_PREFIX`| Existing `/student/api` prefix         |
| `LEGACY_API_PREFIX`    | Existing `/api` prefix                 |
| `ONESIGNAL_APP_ID`     | OneSignal app id (per environment)     |
| `*_TIMEOUT_MS`         | Dio timeouts                           |
| `RETRY_COUNT`          | Idempotent request retries             |
| `ENABLE_LOGGING`       | Pretty Dio logger + verbose logger     |

### iOS

In `ios/Runner/Info.plist` add (already required by OneSignal):
```xml
<key>UIBackgroundModes</key><array><string>remote-notification</string></array>
```

Enable Push Notifications and Background Modes capabilities in Xcode and add
the OneSignal Notification Service Extension target per OneSignal docs.

### Android

`android/app/src/main/AndroidManifest.xml` requires:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

## Architecture

```
lib/
  app/                    # MaterialApp, shell, routing
  bootstrap.dart          # Env load + ProviderScope
  main_{dev,staging,prod}.dart
  core/
    design/               # tokens + components
    env/                  # AppEnv loader
    error/                # Failures + mapper
    logging/              # AppLogger
    network/              # ApiClient + interceptors + envelope
    storage/              # SecureTokenStore, KvCache
    providers.dart        # core DI
  features/
    _shared/models.dart   # Typed domain models
    student_repository.dart
    providers.dart        # feature DI
    auth/
      data/  domain/  presentation/
    dashboard/
    subjects/
    content_player/
    assignments/
    announcements/
    notifications/
    profile/
    settings/
test/                     # unit + widget tests
```

Each feature is self-contained with its own state controller (Riverpod
`StateNotifier` or `FutureProvider`) and screen widgets, while sharing the
common typed models and the `StudentRepository` for HTTP.

## Authentication

- `POST /api/v1/auth/login` -> `{ access_token, refresh_token, expires_in, user }`
- `POST /api/v1/auth/refresh` -> rotates tokens silently on 401
- `GET  /api/v1/auth/me`     -> validates session on cold start
- `POST /api/v1/auth/logout` -> invalidates server-side
- Tokens persisted via `flutter_secure_storage` (Keychain/EncryptedSharedPrefs)
- 401 triggers `AuthInterceptor` -> refresh -> retry; final failure forces logout
- Role guard rejects non-`student` accounts (`RoleFailure`)

## Push Notifications

- OneSignal initialized after first authenticated session
- Soft pre-prompt before native permission
- `OneSignal.login(studentId)` to bind external id
- Player id sent to `POST /api/v1/push/register-device`
- On logout: device unregistered + `OneSignal.logout()`
- Foreground notifications added to local inbox + system banner shown
- Tap routing by `additional_data.deep_link` or category mapping

## Video Watch Flow

1. `GET /student/api/content/:id/embed` -> secure embed url
2. `GET /student/api/content/:id/resume` -> resume position + completion %
3. Every 15s while playing & app foregrounded:
   - `POST /student/api/watch-heartbeat` (legacy, anti-fraud capped)
   - `POST /api/student/watch-events` (granular event log)
4. App lifecycle pause / dispose -> final flush

## Backend Migration Notes

The existing portal uses session/form auth. To support mobile, add the
following endpoints (response body must follow the standard envelope:
`{ success, data?, error? }`):

### Auth (mobile-first v1)
- `POST /api/v1/auth/login`     `{ email, password, device_id? }`
- `POST /api/v1/auth/refresh`   `{ refresh_token }`
- `POST /api/v1/auth/logout`    (Bearer)
- `GET  /api/v1/auth/me`        (Bearer)

JWT recommended; rotate refresh tokens on each refresh and bind to device id.

### Student v1
- `GET  /api/v1/student/dashboard`
- `GET  /api/v1/student/assignments?type=&status=&page=&limit=`
- `GET  /api/v1/student/assignments/:id`
- `POST /api/v1/student/assignments/:id/submit`  (multipart: text_content, attachment)
- `GET  /api/v1/student/quizzes`
- `GET  /api/v1/student/profile`
- `PATCH /api/v1/student/profile/phone`          `{ phone }`
- `POST /api/v1/student/profile/change-password` `{ current_password, new_password }`

### Notifications v1 (unified)
- `GET  /api/v1/notifications`
- `POST /api/v1/notifications/mark-read`         `{ notification_id }`
- `POST /api/v1/notifications/mark-all-read`

### Push device registration
- `POST /api/v1/push/register-device`   `{ player_id, platform, app_version, device_model, os_version }`
- `POST /api/v1/push/unregister-device` `{ player_id }`
- `POST /api/v1/push/test`              (admin) `{ user_id, title, body, deep_link?, category? }`

### Backward compatibility

The `StudentRepository` falls back to the existing `/student/api/*` and
`/api/student/*` routes when v1 returns 404, so the app works with the
current backend during the migration window.

## Testing

```bash
flutter test
```

Unit tests cover:
- Auth interceptor token attachment
- Error mapper status -> `AppFailure` mapping
- Domain model JSON parsing
- Login form validation widget test

Add an integration test under `integration_test/` for the
login -> dashboard -> player -> logout flow once a staging environment is
available.

## Troubleshooting

- "AppEnv not initialized" — ensure your entrypoint calls `bootstrap(Flavor.x)`.
- "Missing env key" — verify the `.env.{flavor}` asset has all required keys.
- iOS push not arriving — confirm APNs key is uploaded to OneSignal and the
  Notification Service Extension is added per OneSignal Flutter setup.
- Android push silent — request `POST_NOTIFICATIONS` runtime permission on 13+.
- 401 loop — backend refresh response must include `access_token` (and ideally
  `refresh_token` + `expires_in`).
# LoayMohamed_MobileApp
