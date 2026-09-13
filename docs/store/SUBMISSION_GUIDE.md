# Going live — App Store and Google Play

Everything each console asks for, in the order it asks, with the value to enter.
Prepared 2026-09-12 for **Loay Motawie 1.0.5 (10)**.

**Key:** ✅ ready · ✏️ you fill in · ⛔ blocks submission until done

---

## 0. Blockers

Neither store will accept the app until these are done.

| # | What | Who | Why it blocks |
|---|---|---|---|
| 1 | Publish the privacy policy at `https://loaymotawie.com/privacy` | You | Both consoles require a working URL before you can submit. Draft: `docs/store/PRIVACY_POLICY_DRAFT.md` |
| 2 | Account deletion: the backend route, plus a page at `https://loaymotawie.com/delete-account` | Backend | Apple 5.1.1(v): the in-app button must actually work. Google: the Data safety form needs the web URL. Spec: `docs/mobile/BACKEND_ACCOUNT_DELETION.md` |
| 3 | A test account for the reviewers | You | The app is login-only. Without credentials both stores reject it. See §1. |
| 4 | Upload build **1.0.5 (10)** | Me, then you | 1.0.5 (9) still says "LoayMohamed" under the icon, and its Android version declares photo and video permissions that Google restricts |
| 5 | Android upload key: create the keystore and fill in `android/key.properties` | You | Google Play refuses debug-signed builds |
| 6 | A closed test with **12 or more testers for 14 days** | You | Required for personal Play accounts before Google grants production access |
| 7 | A public support email address | You | Google shows it on the listing, and Apple needs a contact for App Review |

Recommended, not blocking:

- **Faster video start** (server side): `docs/mobile/BACKEND_VIDEO_STREAMING.md`. A slow start is not a rejection reason in itself; a video that never starts is.
- **Bundled fonts**, so a reviewer on a restricted network does not see the system font.

---

## 1. The reviewer account

Create a **new** student account used only for review:

- enrolled in a class that has lesson videos, at least one homework, one quiz and a few notifications, so every screen has content;
- not a real student — the video watermark shows the account's name and phone number;
- with a password you use nowhere else.

Enter it in App Store Connect (App Review Information) and in Play Console (App content → App access). Nowhere else: not in the listing, and not in this repository.

Keep it enrolled and working after approval. Apple reviews every update with it.

---

## 2. Apple — App Store Connect

### 2.1 Create the app — Apps → ＋ → New App

| Field | Value |
|---|---|
| Platforms | iOS |
| Name | `Loay Motawie` |
| Primary language | English (U.K.) — matches the British spelling in the listing ✏️ |
| Bundle ID | `com.loaymohamed.app` |
| SKU | `loaymotawie-ios` (any unique string; never shown) |
| User access | Full access |

### 2.2 App Information

| Field | Value |
|---|---|
| Subtitle | `Your maths lessons & homework` ✏️ change it if your classes are not all maths |
| Category | Primary **Education**; no secondary |
| Content rights | "Does your app contain, show, or access third-party content?" → **No**, if you own every lesson ✏️ |
| Age rating | See §2.3 |

### 2.3 Age rating questionnaire

Answer **None** or **No** to every content question: violence, sexual content, profanity, horror, alcohol and drugs, gambling, contests, medical information. For the capability questions:

| Question | Answer | Why |
|---|---|---|
| Unrestricted web access | No | The in-app player only opens an allowlist of video hosts |
| User-generated content | No | Homework goes privately to the teacher; nothing is shown to other users |
| Messaging or chat | No | — |
| Advertising | No | — |

Expected rating: **4+**.

### 2.4 Pricing and Availability

| Field | Value |
|---|---|
| Price | Free |
| Availability | ✏️ All countries, or only the ones you teach in |

### 2.5 App Privacy

- **Privacy Policy URL:** `https://loaymotawie.com/privacy` ⛔
- **Data types:** exactly as in `docs/store/PRIVACY_ANSWERS.md`, Apple section — tracking **No**; ten data types, all linked to the user, none used for tracking.

### 2.6 The version page — iOS App 1.0.5

| Field | Value |
|---|---|
| iPhone screenshots (6.9") | `store_assets/app-store/iphone-6.9/` — 1320 × 2868 |
| iPad screenshots (13") | `store_assets/app-store/ipad-13/` — 2064 × 2752 |
| Promotional text | From `docs/store/STORE_LISTING.md` ✅ |
| Description | From `docs/store/STORE_LISTING.md` ✅ |
| Keywords | `edexcel,igcse,maths,math,as level,a level,o level,homework,quiz,lessons,revision,calculus,algebra` ✅ |
| Support URL | `https://loaymotawie.com/contact` ✅ |
| Marketing URL | `https://loaymotawie.com` ✅ |
| Version | `1.0.5` |
| Copyright | `2026 <your legal name or company>` ✏️ |
| Build | **1.0.5 (10)** ⛔ |

Apple derives the smaller iPhone and iPad sizes from these two sets. Upload in the numbered order: the first two or three are what people see in search results.

### 2.7 App Review Information

| Field | Value |
|---|---|
| Sign-in required | Yes |
| User name and password | The reviewer account from §1 ✏️ |
| Contact first name, last name, phone, email | ✏️ Someone who can answer during review |
| Notes | The text in §4 |

### 2.8 Version release

Choose **Manually release this version**, so an approval cannot go live before you are ready.

### 2.9 Export compliance

Already answered inside the build (`ITSAppUsesNonExemptEncryption = false`), so App Store Connect does not ask.

### 2.10 Submit

Add for Review → Submit to App Review. Review usually takes one to two days, and the app is tested on an iPhone **and** an iPad.

---

## 3. Google Play Console

### 3.1 Create app

| Field | Value |
|---|---|
| App name | `Loay Motawie` |
| Default language | English (United Kingdom) – en-GB ✏️ |
| App or game | App |
| Free or paid | Free. This cannot be changed to paid later. |
| Declarations | Tick Developer Program Policies and US export laws |

### 3.2 App content — Policy and programmes → App content

Everything here must be complete before **any** release, including the closed test.

| Section | Answer |
|---|---|
| Privacy policy | `https://loaymotawie.com/privacy` ⛔ |
| App access | **All or some functionality is restricted.** Add one set of instructions named "Student account" with the reviewer's email or phone and password from §1 ✏️ |
| Ads | **No**, my app does not contain ads |
| Content rating | See §3.3 |
| Target audience | **13–15, 16–17 and 18 and over.** Do not select under 13: that brings in the Families policy, which puts extra rules on every SDK, OneSignal included |
| News app | No |
| Data safety | As in `docs/store/PRIVACY_ANSWERS.md`, Google section. Deletion URL `https://loaymotawie.com/delete-account` ⛔ |
| Government app | No |
| Financial features | My app doesn't provide any financial features |
| Health apps | No |
| Advertising ID | **No.** The build does not declare the `AD_ID` permission — checked in the compiled app |
| Photo and video permissions | Not required from 1.0.5 (10), which declares none. Build 9 did, through a library |

### 3.3 Content rating — the IARC questionnaire

| Question | Answer |
|---|---|
| Email for rating certificates | ✏️ |
| Category | Reference, News, or Educational |
| Violence, sexuality, language, controlled substances, crude humour, gambling | No, to every question |
| Can users interact or exchange content? | **No.** Homework goes privately to the teacher; there is no chat, messaging or public profile |
| Shares the user's location | No |
| Digital purchases | No |

Expected rating: Everyone, PEGI 3, USK 0.

### 3.4 Main store listing — Grow → Store presence → Main store listing

| Field | Value |
|---|---|
| App name | `Loay Motawie` (12 of 30) ✅ |
| Short description | `Class videos, homework, quizzes and progress for Loay Motawie's students.` (73 of 80) ✅ |
| Full description | From `docs/store/STORE_LISTING.md` ✅ |
| App icon | `store_assets/google-play/icon-512x512.png` — 512 × 512 ✅ |
| Feature graphic | `store_assets/google-play/feature-graphic-1024x500.png` — 1024 × 500 ✅ |
| Phone screenshots | `store_assets/google-play/phone/` — 1080 × 1920 |
| 7- and 10-inch tablet screenshots | `store_assets/google-play/tablet/` — optional |
| App category | Education |
| Tags | ✏️ Up to five, e.g. Education, Learning, Study, Homework |
| Email address | ✏️ Public support address ⛔ |
| Website | `https://loaymotawie.com` |

### 3.5 Release — the personal-account path

Production stays locked until a closed test has run.

1. **Create the upload key.** Do it once, and back the file up somewhere safe: losing it means the app can never be updated.

   ```bash
   keytool -genkey -v -keystore ~/loay-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

   Copy `android/key.properties.example` to `android/key.properties` and fill it in. It is gitignored.
2. **I build the bundle**: `flutter build appbundle --release` → `build/app/outputs/bundle/release/app-release.aab`.
3. **Testing → Closed testing → Create track.** Upload the `.aab`. When asked about signing, accept **Play App Signing**: Google keeps the app signing key, you keep the upload key.
4. **Testers.** Add at least 12 Google accounts, as an email list or a Google Group. Send them the opt-in link; each must accept, then install from Play. Aim for 15 to 20, so a few dropping out does not break the count.
5. **Wait 14 days.** The testers must stay opted in for 14 continuous days.
6. **Dashboard → Apply for production.** Google asks how the test went; answer plainly.
7. **Production → Create new release** with the same build. New apps can take several days to review.

Release notes for every track:

```
<en-GB>
First release: lesson videos, homework, quizzes and progress in one place.
</en-GB>
```

---

## 4. Notes for the reviewers

Paste into App Store Connect → App Review Information → Notes. The same text works as the Play Console App access instructions.

```
Loay Motawie is the app for students enrolled in Loay Motawie's classes.

Sign in: Student tab, then Email (or Mobile), with the test account provided.

Where things are:
- Lesson videos: Subjects, open a subject, Videos.
- Homework and quizzes: the Tasks tab.
- Account deletion: Profile, Delete account (confirms with the password).

About the video player:
- A watermark with the student's name, phone number and account ID is drawn
  over lessons to discourage copying. It is intentional.
- If screen recording or mirroring starts, playback pauses behind a notice,
  to protect the teacher's lessons.

Parents sign in on the Parent tab with a one-time SMS code. That needs a phone
number the school has linked to a student, so please use the student account.

The app has no in-app purchases. Enrolment and payment are handled by the
school outside the app.
```

✏️ Check the last paragraph is true before pasting it.

---

## 5. Assets in this repository

Every image is generated by `tools/store_screenshots.py` from simulator
captures. Re-run it after retaking any capture.

| Folder or file | Where it goes | Files | Size |
|---|---|---|---|
| `store_assets/app-store/iphone-6.9/` | App Store → iPhone 6.9" Display (required) | 6 | 1320 × 2868 |
| `store_assets/app-store/iphone-6.3/` | App Store → iPhone 6.3" Display (optional) | 6 | 1206 × 2622 |
| `store_assets/app-store/ipad-13/` | App Store → iPad 13" Display (required while iPad is supported) | 6 | 2064 × 2752 |
| `store_assets/google-play/phone/` | Play → Phone screenshots | 6 | 1080 × 1920 |
| `store_assets/google-play/tablet/` | Play → 7-inch **and** 10-inch tablet screenshots | 6 | 2064 × 2664 |
| `store_assets/google-play/icon-512x512.png` | Play → App icon | 1 | 512 × 512 |
| `store_assets/google-play/feature-graphic-1024x500.png` | Play → Feature graphic | 1 | 1024 × 500 |

The six screens, in upload order:

1. Home
2. Lesson videos, grouped by topic
3. Homework and quizzes
4. Notifications
5. A marked homework, with score and feedback
6. Home in dark mode

Notes:

- The 6.9" iPhone set is the 6.3" capture scaled up by 9.45%. The two screens
  have the same shape to within 0.07%, so nothing is stretched. It was needed
  because the Mac's disk was too full to install the app on a 6.9" simulator.
- Every image is RGB with no transparency, which Google Play requires.
- The iOS status bar and home indicator are cropped out of the Play images, so
  no iOS system UI appears on the Android listing.
- The Profile screen is left out on purpose: it shows the account's email and
  phone numbers.
- These were captured from a build that predates four small fixes going into
  1.0.5 (10). Screen 2 will number lessons from #1 within each group and show
  a white status bar over the class header; screen 5 will show the due date
  instead of "Overdue · 14 days". Retake 2 and 5 after installing build 10 if
  you want the screenshots to match it exactly. The others are unaffected.

