# Privacy answers — App Store "App Privacy" and Google Play "Data safety"

Filled in from the code as of 2026-09-11, not from assumptions. Each row says
where the data comes from, so a later change to the app can be traced to the
row it affects. You submit these: the declarations are yours as the publisher.

## The short version

- **No tracking, no ads, no analytics or crash-reporting SDKs, no location, no
  contacts, no payments.**
- Everything collected is **linked to the student's account** and used to run
  the app.
- One third party receives data: **OneSignal**, for push notifications.

## What the app collects, and where

| Data | Where in the code | Why |
|---|---|---|
| Name, email, phone, parent's phone | `POST /auth/register`, profile edits | The account |
| School, grade | Registration, profile | Class placement |
| Account ID | Every signed-in request; also given to OneSignal (`OneSignal.login(userId)`) | The account; sending push to the right person |
| Push device ID, device model, OS version, app version, platform | `POST /devices/register` (`push_service.dart`) | Delivering notifications |
| Profile photo | `uploadProfileImage` | Shown on the profile |
| Homework text, photos and files | `submitAssignment` (`text_content`, `attachments[]`) | Handing in work |
| Video progress: position, seconds watched, playback speed, whether the app was in front | `sendWatchEvent`, heartbeat | Resuming, and progress for student and teacher |
| Screenshot and screen-recording events on lesson content, with the lesson ID and time | `postSecurityEvent` (`/api/security/event`) | Content protection. **Not received today** — the route does not exist, so these 404. Declare it anyway (see below). |

## Apple — App Privacy

- **Does this app collect data?** Yes.
- **Is any of it used for tracking?** No.

For every type below: **linked to the user — Yes; used for tracking — No.**

| Apple category → type | Purpose to tick |
|---|---|
| Contact Info → Name | App Functionality |
| Contact Info → Email Address | App Functionality |
| Contact Info → Phone Number | App Functionality |
| User Content → Photos or Videos | App Functionality |
| User Content → Other User Content | App Functionality |
| Identifiers → User ID | App Functionality |
| Identifiers → Device ID | App Functionality |
| Usage Data → Product Interaction | App Functionality |
| Diagnostics → Other Diagnostic Data | App Functionality, Other Purposes |
| Other Data → Other Data Types (school, grade) | App Functionality |

Two notes:

- **Declare the screenshot events now**, under Diagnostics, even though the route
  is not live. If the backend adds it later, collection starts without an app
  update, and the label would then be wrong.
- **The app's privacy manifest now matches this list**
  (`ios/Runner/PrivacyInfo.xcprivacy`, updated 2026-09-11). It takes effect
  from the next build. The 1.0.5 (8) IPA still carries the older, shorter
  declaration, and it cannot be your submission build anyway: it predates
  in-app account deletion.

## Google Play — Data safety

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | Yes |
| Is all of the user data collected by your app encrypted in transit? | Yes — every request is HTTPS |
| Do you provide a way for users to request that their data is deleted? | Yes — **but only once** the deletion route and web page exist (`docs/mobile/BACKEND_ACCOUNT_DELETION.md`) |

**Shared:** none. OneSignal processes data on your behalf to send notifications,
which Google treats as a service provider, not as sharing.

**Collected** — for each, answer *not processed ephemerally*.

| Google category → type | Required or optional | Purposes |
|---|---|---|
| Personal info → Name | Required | App functionality, Account management |
| Personal info → Email address | Required | App functionality, Account management |
| Personal info → Phone number | Required | App functionality, Account management |
| Personal info → User IDs | Required | App functionality, Account management |
| Personal info → Other info (school, grade, parent's phone) | Required | App functionality |
| Photos and videos → Photos | Optional | App functionality |
| Files and docs → Files and docs | Optional | App functionality |
| App activity → App interactions | Required | App functionality |
| App activity → Other user-generated content | Optional | App functionality |
| App info and performance → Diagnostics | Required | App functionality; Fraud prevention, security, and compliance |
| Device or other IDs → Device or other IDs | Required | App functionality |

## Other declarations both stores ask for

| Question | Answer | Why |
|---|---|---|
| Export compliance (Apple) | Already answered in the build: `ITSAppUsesNonExemptEncryption = false` | The app only uses standard HTTPS |
| Age rating (Apple) | Expect the lowest rating | No objectionable content. Homework goes only to the teacher, so it is not content other users see. The in-app browser is locked to an allowlist, so answer "No" to unrestricted web access. |
| Content rating (Google, IARC) | Education; no violence, gambling or purchases; users do **not** share content publicly | Same reasons |
| Target audience (Google) | **13–15, 16–17 and 18+.** Do **not** tick under 13. | Ticking under 13 puts the app under Google's Families policy, which adds rules for every SDK, OneSignal included. Secondary-school students are 13 and over. |
| Ads (Google) | No ads | — |
| App access (both) | **Login required** — give the reviewers a test account | Without one, both stores reject the app. Enter it in each console's review section, never anywhere public. |
