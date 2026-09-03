# OGS Center — Instructor Mobile App
## Full UI/UX, Design System & Widget Specification (Hand-off Brief)

> **Purpose:** This document is a complete visual/UX brief intended to be handed to another Copilot/agent to build a **separate Flutter mobile app for instructors (teachers)** in the OGS Center education platform. It mirrors the design language of the existing student app (`ogs_center_revamp`) so both apps feel like one product family. It describes look-and-feel, color system, typography, navigation, screen layouts, every reusable widget, every empty/loading/error state, icons, motion, and the instructor-side feature surface.
>
> **What this document is NOT:** It does not include backend API contracts. Those live in [API_ANALYSIS.md](lib/API_ANALYSIS.md), [PAYMENT_INSTUCTOR.md](PAYMENT_INSTUCTOR.md) and [plan_ogsCenterRevamp.prompt.md](plan_ogsCenterRevamp.prompt.md). The instructor app needs its own backend endpoints (TBD), but this brief is purely about **UI/UX/design**.

---

## 1. Product One-Liner

> A clean, navy-and-gold Flutter app that lets instructors see today's classes, take attendance, approve/decline payment & registration requests, view earnings, message parents/students, and review ratings — all from a phone, with a polished, animated, education-grade interface.

**Platform:** Flutter (Material 3) · Android · iOS  
**Design language:** Modern educational, **Navy + Gold**, generous whitespace, soft shadows, 16 px rounded corners, subtle motion.  
**Audience:** Teachers / class instructors. **Locale:** English (LTR) primary; Arabic-ready (RTL).

---

## 2. Brand & Visual Identity

### 2.1 Color Palette (mirror the student app)

| Token | Hex | Usage |
|---|---|---|
| `primary` | `#0B2A4D` | App bar, headers, primary buttons, bottom nav background |
| `primaryLight` | `#1A3F6F` | Gradient end, hover/highlight |
| `primaryDark` | `#061B33` | Splash gradient, deep emphasis |
| `accent` (gold) | `#C9A84C` | CTAs, active nav indicator, badges, FAB |
| `accentLight` | `#E0C875` | Gradient end, soft highlight |
| `accentDark` | `#A88A30` | Pressed accent state |
| `surface` | `#FFFFFF` | Cards, sheets, dialogs |
| `background` | `#F4F6FA` | Scaffold background |
| `divider` | `#E5E7EB` | Hairlines, borders |
| `shadow` | `#0000001A` | Card shadow (10% black) |
| `textPrimary` | `#0D1B2A` | Main text |
| `textSecondary` | `#6B7280` | Sub text, labels |
| `textHint` | `#9CA3AF` | Placeholder, disabled text |
| `textOnPrimary` | `#FFFFFF` | Text over navy/primary |
| `textOnAccent` | `#0D1B2A` | Text over gold/accent |

**Semantic colors**

| Token | Hex | Usage |
|---|---|---|
| `error` | `#E53935` | Destructive, validation errors, "Rejected" |
| `errorLight` | `#FFF0F0` | Soft error background |
| `success` | `#2E7D32` | Approved, positive state |
| `successLight` | `#E8F5E9` | Soft success background |
| `warning` | `#F57F17` | Pending state, attention |
| `warningLight` | `#FFF8E1` | Soft warning background, unread notification row |
| `info` | `#1565C0` | Informational chips |
| `infoLight` | `#E3F2FD` | Soft info background |

**Status badges** (used everywhere requests appear)

| Status | BG | Text |
|---|---|---|
| `pending` | `#FFF3E0` | `#E65100` |
| `approved` | `#E8F5E9` | `#2E7D32` |
| `cancelled` | `#F3E5F5` | `#7B1FA2` |
| `rejected` | `#FFEBEE` | `#C62828` |

**Gradients**

```dart
primaryGradient = topLeft→bottomRight [#0B2A4D → #1A3F6F]
accentGradient  = topLeft→bottomRight [#C9A84C → #E0C875]
splashGradient  = topCenter→bottomCenter [#061B33 → #0B2A4D → #1A3F6F]
```

### 2.2 Typography (Google Fonts)

- **Display & headings:** `Outfit` (semi-bold / bold)
- **Body & inputs:** `Inter` (regular)
- **Buttons & nav labels:** `Outfit Medium / SemiBold`

| Style | Font | Weight | Size | Line height |
|---|---|---|---|---|
| `displayLarge` | Outfit | 700 | 28 | 1.3 |
| `headlineMedium` | Outfit | 600 | 22 | 1.3 |
| `titleLarge` | Outfit | 600 | 18 | 1.4 |
| `titleMedium` | Outfit | 600 | 16 | 1.4 |
| `titleSmall` | Outfit | 600 | 14 | 1.4 |
| `bodyLarge` | Inter | 400 | 16 | 1.5 |
| `bodyMedium` | Inter | 400 | 14 | 1.5 |
| `bodySmall` | Inter | 400 | 12 | 1.5 |
| `labelLarge` | Outfit | 500 | 14 | 1.4 |
| `labelMedium` | Outfit | 500 | 12 | 1.4 |
| `labelSmall` | Outfit | 500 | 11 | 1.4 |
| `button` | Outfit | 600 | 15 | 1.2 / +0.5 ls |
| `caption` | Inter | 400 | 11 | +0.3 ls |
| `overline` | Outfit | 600 | 10 | +1.2 ls |

### 2.3 Shape, Elevation & Spacing

- **Corner radius:** `12` for buttons/inputs, `16` for cards, `20` for dialogs, `24` for bottom sheets (top corners only).
- **Card elevation:** `2` with shadow `#0000001A`, blur 12, offset `(0, 4)`.
- **Spacing scale:** `4 / 8 / 12 / 16 / 20 / 24 / 32` px.
- **Default screen padding:** horizontal `16`, vertical `12–24`.
- **Touch target:** minimum `48 × 48`.

### 2.4 Iconography

Use **Material Symbols (Rounded)** only. Outlined for inactive, filled-rounded for active (matches student app).

| Concept | Icon |
|---|---|
| Home / Dashboard | `home_outlined` / `home_rounded` |
| Classes | `class_outlined` / `class_rounded` |
| Today's schedule | `today_rounded`, `event_rounded` |
| Attendance | `check_circle_outline` / `check_circle_rounded`, `qr_code_scanner_rounded` |
| Students | `people_alt_outlined` / `people_alt_rounded`, `school_rounded` |
| Payments / Earnings | `payments_rounded`, `account_balance_wallet_rounded` |
| Pending requests | `pending_actions_rounded`, `hourglass_top_rounded` |
| Approve | `check_rounded` |
| Reject | `close_rounded` |
| Notifications | `notifications_outlined` / `notifications_rounded` (with red dot badge) |
| Messages | `chat_bubble_outline_rounded` |
| Profile | `person_outline_rounded` / `person_rounded` |
| Contact / Help | `contact_support_outlined` / `contact_support_rounded` |
| Search | `search_rounded` |
| Filter | `filter_list_rounded` |
| Sort | `swap_vert_rounded` |
| Add | `add_rounded`, raised in nav: `app_registration_rounded` |
| Camera / Scanner | `camera_alt_rounded`, `qr_code_scanner_rounded` |
| Image upload | `image_outlined`, `cloud_upload_rounded` |
| Settings | `settings_rounded` |
| Logout | `logout_rounded` |
| Rating | `star_rounded`, `star_outline_rounded` |
| Time slots | `schedule_rounded` |
| Currency / EGP | `attach_money_rounded` |
| Edit | `edit_rounded` |
| Delete | `delete_outline_rounded` |
| WhatsApp | `font_awesome:whatsapp` |
| Phone | `phone_rounded` |
| Email | `mail_outline_rounded` |
| Location | `location_on_outlined` |
| Back | `arrow_back_rounded` |
| Forward | `arrow_forward_ios_rounded` (16) |
| Refresh | `refresh_rounded` |
| Info | `info_outline_rounded` |
| Empty box | `inbox_rounded` |

App brand mark: re-use `assets/images/ogshub.jpg` / `ogshub_icon.png` and `MubarmijLogo.jpeg` from this repo to maintain brand parity.

---

## 3. Material 3 Theme Specification

Use Material 3 (`useMaterial3: true`) with `ColorScheme.fromSeed(seedColor: #0B2A4D)` overridden by the palette above.

**App bar:** primary navy bg, white foreground, elevation 0, centered title, Outfit 18/600.
**Cards:** white bg, elev 2, radius 16, 16h × 6v margin.
**Elevated buttons:** primary navy bg, white text, radius 12, padding 24×14, Outfit 15/600 +0.5 ls.
**Outlined buttons:** primary text + 1.5 px primary border, radius 12.
**Text buttons:** primary text, no bg.
**Inputs:** filled white, radius 12, divider border, primary 2 px focused, error red border, Inter 14 hint/label.
**Bottom sheet:** white, top corners 24, with drag handle (`#E5E7EB`).
**Dialogs:** white, radius 20, Outfit 18/600 title, Inter 14 body.
**Chips:** background `#F4F6FA`, selected accent 20%, radius 20, Outfit 12/500.
**Snackbar:** dark text-primary bg, white text, radius 12, **floating** behavior.
**FAB:** accent gold bg, dark text, radius 16, elev 4.
**Progress indicator:** accent gold.
**Tab bar (in app bar context):** white labels, 3 px gold underline indicator, Outfit 14/700 selected.
**Bottom navigation:** custom (see §4) — navy bg, gold active, white-60% inactive, raised center button.

---

## 4. Navigation Architecture

### 4.1 Bottom Nav Shell (5 tabs, raised center)

A **persistent bottom bar** with `extendBody: true`, white surface, top shadow `#0B2A4D14`, 68 px tall, safe-area aware. The middle slot is a **raised floating circle** (56×56, gold gradient, 3 px white border, accent shadow) that sits 18 px above the bar.

```
┌──────────────────────────────────────────────────────────┐
│   [Home]   [Classes]   ◉ TAKE   [Requests]   [Profile]   │
└──────────────────────────────────────────────────────────┘
```

| Slot | Icon (inactive → active) | Label | Destination |
|---|---|---|---|
| 0 | `home_outlined` → `home_rounded` | Home | Today's dashboard |
| 1 | `class_outlined` → `class_rounded` | Classes | All classes list |
| 2 | **Raised** `qr_code_scanner_rounded` | Take | Scan attendance / quick attendance |
| 3 | `pending_actions_outlined` → `pending_actions_rounded` (with badge) | Requests | Approval inbox |
| 4 | `person_outline_rounded` → `person_rounded` | Profile | Instructor profile |

Active label color = **accent gold**, inactive = `textSecondary`.
Use `StatefulShellRoute.indexedStack` in `go_router` so each tab keeps its state.

### 4.2 App Bar Pattern

- Navy background, white title centered (Outfit 18/600).
- Leading: back arrow on push routes; on dashboard root → menu/avatar.
- Trailing on Home: **bell** icon with red-dot **badge** for unread notifications + **search**.
- On list screens: search icon + filter icon.

### 4.3 Routes (suggested)

```
/welcome                 → Splash + session check
/login                   → Instructor login
/forgotPassword          → Sheet
/whatsappOtp             → 6-digit OTP confirm
/main                    → MainShell (5 tabs)
   /home                 → Today dashboard
   /classes              → Classes list
   /take                 → Quick-take attendance / QR scan
   /requests             → Approvals inbox (Payments · Registrations · Attendance)
   /profile              → Instructor profile
/classDetails/:id        → Class details + roster + sessions
/sessionDetails/:id      → Single session: roster check-in
/studentProfile/:id      → Student snapshot
/attendanceMark          → Bulk mark attendance for a session
/qrScanner               → Camera QR scanner
/paymentRequestDetails/:id → Approve/decline a payment
/registrationRequestDetails/:id → Approve/decline a registration
/notifications           → Notifications list
/earnings                → Earnings & payouts
/ratings                 → Ratings & reviews from students
/scheduleEditor          → Add/edit class session
/messages                → Conversations list
/chat/:peerId            → Chat thread
/contact                 → Help & contact center
/settings                → Account, notifications, language
/changePassword          → Sheet
/about                   → About / version / legal
/forceUpdate             → Blocking update screen
/success                 → Generic success
/failure                 → Generic failure
```

---

## 5. Screen-by-Screen Layout & Widget Map

> Every screen below specifies: **purpose**, **app-bar**, **body composition**, **empty state**, **loading state**, **error state**, **interactions**, and **navigation out**. All cards/lists use the reusable widgets defined in §6.

### 5.1 Splash / Welcome
- Full-screen `splashGradient` (navy → light navy).
- Centered logo (`assets/images/ogshub_icon.png`, 96 × 96, white border, soft glow).
- Below: "OGS Center · Instructor" in Outfit 22/700 white.
- Sub-line: "Empower your classroom" in Inter 14 white-70%.
- Bottom: `SpinKitThreeBounce` (gold).
- Auto-route after 2 s based on session.

### 5.2 Login
- Navy gradient header (top 35%) with logo + greeting "Welcome back, Coach".
- White card (radius 24 top) sliding up over the background:
  - **Tab 1 — Sign in:**
    - `AppTextField` mobile (phone icon prefix).
    - `AppTextField` password (lock prefix, eye toggle suffix).
    - `Forgot password?` text button (right aligned).
    - `AppButton.primary("Sign In", loading: …)` full-width.
    - "Don't have an account? Contact admin" → opens `ContactDialogWidget`.
  - **Tab 2 — Help:** brief card with WhatsApp/phone CTAs.
- Bottom: small version string "v 1.0.0 · OGS Center".

### 5.3 WhatsApp OTP
- Centered: `MubarmijLogo`, headline "Verify your number".
- 6-digit `AppPinField` (pinput, 56×64 boxes, navy border focused, gold filled).
- Resend countdown chip "Resend in 0:60" turning into a `TextButton` after expiry.
- Bottom `AppButton.primary("Confirm")`.

### 5.4 Home (Today Dashboard) — **Primary screen**

**App bar:** "Hi, Dr. {firstName}" + bell (badge) + search.

**Body (vertical scroll, pull-to-refresh):**

1. **Greeting & summary header card** — primary gradient background, radius 20, padding 20.
   - Left: `AvatarInitials` (gold ring, 56), instructor name (Outfit 18/700), subtitle "Mathematics · Grade 10".
   - Right: tiny pills: `📅 3 sessions today`, `👥 47 students`, `⏰ Next 4:30 PM`.
2. **Quick-action row** — 4 square tiles in a horizontal `Wrap` (each 80×80, white, radius 16, soft shadow, icon + label):
   - `qr_code_scanner_rounded` "Scan" → /take
   - `add_rounded` "Add session" → /scheduleEditor
   - `payments_rounded` "Earnings" → /earnings
   - `chat_bubble_rounded` "Messages" → /messages
3. **Today's Sessions** — section header "Today" (Outfit 18/700) + `See all` text button.
   - Horizontal list of `SessionCard` (see §6.7), 280-wide, scroll snap, padding 16.
   - Empty: `EmptyState(icon: today_rounded, title: 'No sessions today', subtitle: 'Enjoy the day or schedule a class')`.
4. **Pending requests** — section "Awaiting your approval".
   - `RequestSummaryCard` × 3 (one per type: Payments / Registrations / Attendance) — gold accent left border, count chip, `›` chevron.
   - Empty: `EmptyState(icon: inbox_rounded, title: 'All caught up', subtitle: 'No pending requests right now')`.
5. **This week at a glance** — `StatGrid` (2 × 2):
   - "Classes" / "Attendance %" / "New students" / "Earnings (EGP)" — each a `StatCard`.
6. **Recent activity** — `TimelineItem` list (last 5 events).

**Loading state:** all sections show `SkeletonLoader` shimmer cards (matched to final shape).
**Error state:** `EmptyState(icon: cloud_off_rounded, title: 'Could not load dashboard', subtitle: '...', action: AppButton.outlined('Retry'))`.

### 5.5 Classes (Tab 1)
- App bar: title "My Classes" + search + filter.
- **Sticky search bar** (rounded 12 input).
- **Filter chips row** (horizontal scroll): All / Active / Upcoming / Passed.
- Vertical list of `ClassCard` — 100% width (in this app), each card showing:
  - Header strip with gradient (navy default; **passed** = grey gradient; **upcoming** = blue).
  - Title (`display_name`), educational system chip.
  - Row: `school_rounded` Grade · `people_alt_rounded` 32 students · `schedule_rounded` Mon/Wed 5 PM.
  - Footer: "Next session: Today 5 PM" + chevron.
- Empty: `EmptyState(icon: class_rounded, title: 'No classes yet', subtitle: 'Ask the admin to assign you a class')`.

### 5.6 Class Details
- Hero header (180 h) with primary gradient + class name + chips (system, students count).
- `TabBar` (in app bar context, white labels, gold underline):
  - **Roster** — searchable list of student rows: `AvatarInitials` + name + mobile, trailing chip "Active / Pending payment / Blocked".
  - **Sessions** — list grouped by date; each is `SessionCard` with status (Upcoming · Live · Done).
  - **Requests** — same `RequestRow` widget as inbox, scoped to this class.
  - **Stats** — `StatCard` grid + `LineChart` (fl_chart) of attendance % week-by-week.
- FAB: `add_rounded` "New session".
- Each tab has its own empty state.

### 5.7 Take (Center Tab) — Quick attendance
- Full-screen with two large CTAs stacked:
  - **Big primary card** "Scan student QR" (gold gradient, large `qr_code_scanner_rounded`, 96 px) → opens scanner.
  - **Secondary card** "Manual mark by class" (outlined navy, `class_rounded`) → list of today's sessions to choose.
- After scan / pick: navigates to **Mark Attendance** screen.

### 5.8 QR Scanner
- Full-screen camera (`mobile_scanner`) with **scan window overlay** (rounded square, gold corners, dim outside).
- Top: back, flashlight toggle, switch camera.
- Bottom sheet (peeked): "Last scanned: Mohamed Ali · 14:22" `BarcodeWidget` thumbnail + `AppButton.primary("Mark Present")`.
- Snackbar feedback for invalid codes.

### 5.9 Mark Attendance (Session)
- App bar: session title + date.
- Header strip: "12 / 32 marked", linear progress bar (gold).
- Search field.
- List of **StudentCheckRow** widgets — each has:
  - `AvatarInitials`, name, mobile, "Last attended 3 days ago".
  - Trailing **3-state segmented control**: `Present` (green), `Absent` (red), `Late` (warning).
  - Optional money field if `paymentType == 'session'`.
- Sticky bottom bar: "Save attendance" (`AppButton.primary`, full width, 56 h).
- Empty roster: `EmptyState(icon: people_outline_rounded, title: 'No students enrolled', action: 'Open registrations')`.

### 5.10 Requests (Tab 3) — Approvals Inbox

**Tabs:** `Payments` · `Registrations` · `Attendance` (badge counts on each tab).

Each tab is a `ListView` of `RequestCard` (see §6.8). On tap → details screen.

Filter row (chips): `All` `Pending` `Approved` `Rejected` + date range.

Empty: `EmptyState(icon: check_circle_rounded, title: 'You're all caught up', subtitle: 'No pending requests')`.

### 5.11 Payment Request Details
- Header: status badge (large), amount in EGP (Outfit 28/700), submitted-by line.
- **InstaPay receipt preview** (`photo_view`, tappable to fullscreen).
- 6 read-only fields (mirrors student-side OCR output): Status, Amount, Date, Reference, Receiver Account, OGS Account Valid — coloured green/red.
- Student card (mini profile + "Open profile" link).
- Notes (if any).
- Sticky footer with two buttons:
  - `AppButton.danger("Decline")` → opens `ConfirmDialog` with reason text field.
  - `AppButton.success("Approve")` → opens `ConfirmDialog` with summary, then triggers API.
- Loading overlay during submit; success → `SuccessScreen`, fail → `FailedResponseScreen`.

### 5.12 Registration Request Details
- Same layout as 5.11 but with class details card (subject, fees, group).
- Shows whether **paid** or **free** request.
- Approve/Decline buttons.

### 5.13 Attendance Request Details
- Same layout, plus session/date and group dropdown summary.

### 5.14 Notifications
- App bar: title "Notifications" + "Mark all read" text button.
- Vertical list of `NotificationItem` (avatar circle by source, title, content, relative time, **unread row tint** `#FFF8E1`, dot indicator).
- Empty: `EmptyState(icon: notifications_off_rounded, title: 'No notifications', subtitle: '...')`.
- On dispose: batch mark read.

### 5.15 Earnings
- Header card: gold gradient, big number "EGP 12,450" + sub "This month".
- Period selector chips: Today / Week / Month / Custom.
- `LineChart` of daily earnings (gold line, soft area fill).
- Below: list of payouts/transactions — `TimelineItem` with currency on right.
- Empty: `EmptyState(icon: payments_rounded, title: 'No earnings yet')`.

### 5.16 Ratings & Reviews
- Header: average rating (giant star + 4.7 + 156 reviews) and a 5-bar histogram.
- Filter chips: 5★ 4★ 3★ 2★ 1★.
- `ReviewItem` list — `AvatarInitials`, student name, `RatingBarIndicator` (read-only), date, review text.
- Empty: `EmptyState(icon: star_outline_rounded, title: 'No reviews yet')`.

### 5.17 Schedule Editor (Add/Edit Session)
- Bottom sheet or full screen (DraggableScrollableSheet from .55 to .95).
- Form: Class dropdown · Date picker · Time picker · Duration · Group dropdown · Capacity · Notes (multiline).
- Sticky footer: Cancel (text button) / Save (primary).

### 5.18 Messages & Chat
- Conversations list: `AvatarInitials`, peer name, last message preview, time, unread bubble (gold).
- Chat thread: bubbles (instructor right, navy bg white text; peer left, white bg text-primary), input bar with paperclip + send (gold round).
- Empty conversation: `EmptyState(icon: chat_bubble_outline_rounded, title: 'Say hi 👋')`.

### 5.19 Profile
- Top: large `AvatarInitials` (96, gold ring + double-circle layered, mirrors student empty-state style), name (Outfit 22/700), specialization chip, `Edit profile` text button.
- Info rows (white card list, dividers): Phone, Email, Specialization, Active classes, Joined date.
- **More settings** (`expandable` panel):
  - Change password → bottom sheet `ChangePasswordWidget`.
  - Notification preferences → `/settings`.
  - Language → switcher (English / العربية).
  - About → `/about`.
- Sticky bottom danger row: `AppButton.outlined.destructive("Sign out")` (icon `logout_rounded`).

### 5.20 Contact / Help
- Card list with icons (WhatsApp green, phone blue, Instagram pink, email navy, location gold) — each row launches the relevant URL via `url_launcher`.
- Bottom card: "Powered by Mubarmij" with logo.

### 5.21 Force Update (blocking)
- Centered illustration (use a Lottie or simple `system_update_rounded` icon in the layered-circles motif).
- Title "Update required".
- Body "A newer version is available. Please update to continue."
- `AppButton.primary("Open store")` deep-links to Play/App Store.
- Non-dismissible (no back).

### 5.22 Success / Failure screens
- Big circular icon (success green check / error red cross) inside layered circles.
- Title (Outfit 22/700) + body subtitle (Inter 14).
- Single CTA `AppButton.primary("Done")` returns to relevant root.

---

## 6. Reusable Widget Library (build these first)

> Mirror the student app's API shapes where helpful (already implemented in [lib/shared/widgets](lib/shared/widgets)). Re-skin/adapt for instructor needs.

### 6.1 `AppButton`
Variants: `primary` (filled navy), `secondary` (filled gold), `outlined` (navy border), `ghost` (text), `success` (green), `danger` (red).
States: idle, **loading** (spinner replaces label, button stays sized), disabled (40% opacity).
Sizes: `sm` (40 h), `md` (48 h, default), `lg` (56 h).
Shape: radius 12, padding 24×14.

### 6.2 `AppTextField`
- Floating Material 3 label, prefix icon optional, suffix optional, error text below, helper text gray.
- Variants: text, password (eye toggle), phone (auto +20 prefix or country code), search (rounded 16, no label, soft fill).

### 6.3 `AppPinField`
- 6 boxes, each 48×56, radius 12, divider border, navy 2 px focused, gold filled when entered. Auto-advance.

### 6.4 `AvatarInitials`
- Circle with `firstletter + lastletter`, navy bg, white Outfit text, accent ring optional, size param.

### 6.5 `StatusBadge`
- Pill, radius 20, padding 12×4, capitalised label.
- Factory: `StatusBadge.fromStatus('Pending' | 'Approved' | 'Rejected' | 'Cancelled')` → maps to colour pair from §2.1.

### 6.6 `ClassCard`
- 280-wide horizontal variant for Home / 100% width for Classes list.
- Rounded 16, white. Top header strip with **status-aware gradient**:
  - `passed` → grey `#616161 → #9E9E9E`.
  - `upcoming` → blue `#0277BD → #039BE5`.
  - `pending request` → orange `#E65100 → #F57C00`.
  - `approved` → green `#1B5E20 → #2E7D32`.
  - default → primary navy gradient.
- Optional border (1.5 px, 50% of border colour) and matching glow shadow when status active.
- Bottom info section: subject title, instructor mini, schedule line, count chips, chevron.

### 6.7 `SessionCard`
- Compact horizontal card for "Today" carousel. Top tag: time (gold pill). Title, group chip, attendees count chip, `Live`/`Upcoming`/`Done` badge.

### 6.8 `RequestCard` / `RequestRow`
- Left coloured strip (4 px) by status: pending=warning, approved=success, rejected=error.
- Avatar (student initials), title (request type + amount), subtitle (class & date), trailing `StatusBadge` + chevron.

### 6.9 `RequestSummaryCard` (dashboard)
- White card, gold accent left border, icon left, count (Outfit 22/700) + label, chevron right.

### 6.10 `StatCard` & `StatGrid`
- 2 × 2 responsive grid; each `StatCard`: icon top-left in tinted circle, value Outfit 22/700, label Inter 12, optional delta chip (`+12% ▲` green / `−4% ▼` red).

### 6.11 `EmptyState`
- **Layered-circles motif** (already in repo): 3 concentric circles (140 / 110 / 80) with subtle accent + primary tints, centered icon (36 px, primary 60%).
- Animated entrance: `scale(.8→1, 500 ms easeOutBack) + fadeIn 400 ms`. Title fades after 150 ms, subtitle 300 ms, action 450 ms (use `flutter_animate`).
- Fields: `icon`, `title`, `subtitle?`, `action?`.

### 6.12 `SkeletonLoader`
- Shimmer placeholder (gray base `#E0E0E0`, highlight `#F5F5F5`) matched to ClassCard / RequestCard / NotificationItem shapes.

### 6.13 `LoadingOverlay`
- Full-screen `Color(0x80000000)` scrim with centered white card containing `SpinKitFadingCube` (gold) + small label.

### 6.14 `ConfirmDialog`
- Radius 20, white. Title (Outfit 18/600), body (Inter 14 secondary), optional `TextField` (e.g., reason). Two buttons in footer: secondary text + primary action.
- Variants: `informational`, `destructive` (primary becomes red).

### 6.15 `ResponseSheet`
- Bottom sheet (24 top radius) with drag handle. Big centered icon + title + body + single CTA. Used for friendly success/error flows that don't warrant a full screen.

### 6.16 `InstapayAccountTile` (still relevant for parent-side displayed receipts)
- Row with `AvatarInitials` (account name initials), account name (titleSmall), number monospaced (bodyMedium), trailing copy + open icons.

### 6.17 `ImageUploadTile`
- 1:1 dashed-border tile (radius 16, primary 30% border, F4F6FA bg) with cloud-upload icon + "Upload receipt" label. Replaces with thumbnail (rounded 12) + remove × button after pick.

### 6.18 `StepIndicator`
- Horizontal pill of N segments (gold filled = done, navy outline = current, gray = upcoming).

### 6.19 `NotificationItem`
- Row: tinted circle icon (per source: payments=gold, attendance=success, system=info), title (titleSmall), content (bodyMedium ellipsised 2 lines), relative time (caption right). Unread → row bg `#FFF8E1` + 8 px gold dot before title.

### 6.20 `TimelineItem`
- Vertical timeline with circular dot + connecting line (divider colour). Right side: title, sub, time chip.

### 6.21 `NoInternetBanner`
- Inline yellow `warningLight` strip at top of body when offline: cloud-off icon + "No internet — showing cached data" + retry text button.

### 6.22 `ForceUpdateSheet` / `ForceUpdateScreen`
- Modal bottom sheet **or** full screen (used at root). Layered circles + system_update icon + body + store CTA.

### 6.23 `CelebrationOverlay`
- Full-screen, transparent, brief confetti / sparkle animation (use existing implementation in [lib/shared/widgets/celebration_overlay.dart](lib/shared/widgets/celebration_overlay.dart)) — fire after a successful approval batch.

### 6.24 `SearchBar` (themed)
- Soft white rounded 12, search icon prefix, clear suffix, `Inter 14` text.

### 6.25 `FilterChipsRow`
- Horizontal scroll of `ChoiceChip` styled per Material 3 + theme: gold-tinted when selected, divider border otherwise.

### 6.26 `BottomActionBar`
- White surface, 16 px padding, shadow above (`#0B2A4D14` blur 16 offset (0,-4)), holds 1–2 buttons stretched.

### 6.27 `SectionHeader`
- Row: title (Outfit 18/700) left, optional `See all` text button right. 8 px bottom padding.

### 6.28 `KeyValueRow`
- For details screens: label (Inter 13 secondary) left, value (Inter 14 primary, semibold) right, divider underneath.

### 6.29 `Tag` / `Pill`
- Small pill (radius 20, padding 10×4) with subtle bg + bold label. Used for educational system, group, time.

---

## 7. Empty / Loading / Error States — Required Coverage

For **every** list screen, the implementation must include all four states:

| State | Pattern |
|---|---|
| **Loading** | `SkeletonLoader` matched to final card shape (no spinners on first load). |
| **Empty** | `EmptyState` widget with the icon/title/subtitle from §5; optional CTA. |
| **Error** | `EmptyState(icon: cloud_off_rounded, title, subtitle, action: AppButton.outlined('Retry'))`. |
| **Offline** | `NoInternetBanner` at top + cached content if available. |

Per-action states:
- **Submitting** → button enters `loading` state (label hides, spinner shows).
- **Optimistic mark / unmark** → row shows tiny gold spinner overlay until server confirms.
- **Snackbar** (floating) for non-blocking feedback ("Marked 12 students present").

---

## 8. Motion & Interaction Patterns

- **Page transitions:** shared-axis horizontal for push routes, fade-through for tab switches. Use `flutter_animate` or Material 3 page transitions.
- **List entrance:** stagger fade + slide-up (40 px) per item, 60 ms delay step, 350 ms total.
- **Empty state entrance:** scale 0.8 → 1 with `easeOutBack` over 500 ms (already used in repo).
- **Approve/Reject:** show `CelebrationOverlay` on bulk success; `Haptics.lightImpact()` on every approve.
- **Pull-to-refresh:** Material indicator tinted gold.
- **Loading overlays:** fade in 200 ms.
- **Tap feedback:** `InkWell` with primary 8% splash, transparent highlight.

---

## 9. Forms, Validation & Inputs

- All forms use `AppTextField` and a single `Form` with `formKey`.
- Inline validators: required, min length, phone (+20 / 11 digits), numeric for amounts.
- On invalid submit: scroll to first error, show floating snackbar "Please fix the highlighted fields".
- Currency input: numeric keyboard, EGP suffix, thousands separator on blur.
- Date/time pickers: themed via `DatePickerThemeData` & `TimePickerThemeData` with primary navy + gold accents.

---

## 10. Accessibility

- Color contrast ≥ 4.5:1 for body text on white/navy.
- Tap targets ≥ 48 dp.
- All icons get `Semantics(label: …)` when standalone.
- Support text scaling up to 1.3× without overflow (use `AutoSizeText` only where needed).
- Focus order is logical; bottom nav is reachable last.
- Respect `MediaQuery.platformBrightness` if a dark theme is added later (keep tokens centralised).

---

## 11. Internationalization Readiness

- Wrap all user-facing strings in `AppLocalizations` (gen-l10n) — start English-only.
- Layout works in **RTL**: use `EdgeInsetsDirectional`, `Align(alignmentDirectional: …)`, mirror back arrows automatically.
- Numeric display via `intl` `NumberFormat.currency(locale: 'en_EG', symbol: 'EGP ')`.
- Dates via `intl` `DateFormat('E, d MMM h:mm a')` (matches student app).

---

## 12. Assets to Provide

| Asset | Purpose |
|---|---|
| `assets/images/ogshub_icon.png` | App icon / splash logo |
| `assets/images/MubarmijLogo.jpeg` | Footer / about |
| `assets/lottie/empty_inbox.json` *(optional)* | Optional empty-state animation |
| `assets/lottie/celebration.json` *(optional)* | Approval celebration |
| `assets/icons/qr_overlay.svg` *(optional)* | QR scanner overlay corners |

(Ship the same brand assets as the student app for a unified family.)

---

## 13. Dependencies (UI-relevant subset)

```yaml
flutter:
  sdk: flutter
flutter_riverpod: ^2.x
go_router: ^12.1.3
google_fonts: ^6.3.3
flutter_animate: ^4.5.0
flutter_spinkit: ^5.2.0
shimmer: ^3.x
flutter_rating_bar: ^4.0.1
barcode_widget: ^2.0.3
mobile_scanner: ^5.x   # QR scan for instructors
photo_view: ^0.15.0
auto_size_text: ^3.0.0
expandable: ^5.0.1
font_awesome_flutter: ^10.7.0
pinput: ^5.x
url_launcher: ^6.3.1
intl: ^0.20.2
timeago: ^3.7.1
fl_chart: ^0.69.x      # earnings/stats charts
image_picker: ^1.1.2
shared_preferences: ^2.5.3
internet_connection_checker_plus: any
package_info_plus: any
```

---

## 14. Folder Structure (suggested)

```
lib/
  core/
    constants/   (route names, app constants, currency, locale)
    theme/       (app_colors.dart, app_text_styles.dart, app_theme.dart  — copy from this repo)
    router/      (go_router with StatefulShellRoute)
    network/     (dio_client.dart, api_response.dart)
    utils/       (validators.dart, formatters.dart, connectivity_service.dart)
  shared/
    models/      (instructor, class, session, student, request, earning, review)
    widgets/     (every widget in §6 — reuse the student app's widgets where possible)
    providers/   (Riverpod app-state, session)
  features/
    auth/         (login, otp, forgot password)
    home/         (today dashboard)
    classes/      (list, details, sessions, roster)
    take/         (quick-take + qr scan + mark attendance)
    requests/     (inbox + payment / registration / attendance details)
    notifications/
    earnings/
    ratings/
    messages/
    schedule/     (session editor)
    profile/
    contact/
    settings/
    shared_results/  (success / failure)
  main.dart
```

---

## 15. Acceptance Checklist for the Other Copilot

- [ ] All colors, fonts, radii, shadows match §2.
- [ ] Material 3 theme applied per §3 (light only for v1).
- [ ] Bottom nav with 5 slots + raised gold center button (§4.1).
- [ ] Every screen in §5 implemented with **loading / empty / error / offline** states.
- [ ] Every reusable widget in §6 created and used at least once.
- [ ] Empty states use the **layered-circles motif** with the entrance animation.
- [ ] Status badges use the exact color pairs in §2.1.
- [ ] Pull-to-refresh on every list screen.
- [ ] Snackbars are floating + radius 12 + dark text-primary background.
- [ ] Bottom sheets have a drag handle and 24 px top radius.
- [ ] Force-update screen exists and is non-dismissible.
- [ ] Profile → sign-out flow with confirm dialog.
- [ ] All icons use Material Symbols Rounded (outlined → filled active swap on nav).
- [ ] App is RTL-safe (use `EdgeInsetsDirectional`).
- [ ] Approve/Decline actions trigger `CelebrationOverlay` on success and `FailedResponseScreen` on failure.

---

## 16. Reference Implementations in This Repo

The other Copilot can lift these widgets verbatim and reskin labels/icons:

- Theme: [lib/core/theme/app_colors.dart](lib/core/theme/app_colors.dart), [lib/core/theme/app_text_styles.dart](lib/core/theme/app_text_styles.dart), [lib/core/theme/app_theme.dart](lib/core/theme/app_theme.dart)
- Bottom nav with raised center button: [lib/features/home/presentation/main_shell.dart](lib/features/home/presentation/main_shell.dart)
- Class card (status-aware gradients): [lib/shared/widgets/class_card.dart](lib/shared/widgets/class_card.dart)
- Empty state (layered-circles motif): [lib/shared/widgets/empty_state.dart](lib/shared/widgets/empty_state.dart)
- All other widgets: [lib/shared/widgets/](lib/shared/widgets)
- Home dashboard composition pattern: [lib/features/home/presentation/home_screen.dart](lib/features/home/presentation/home_screen.dart)

---

**End of brief.** Hand this file plus the `lib/shared/widgets/` and `lib/core/theme/` folders to the other Copilot and instruct it to: *"Build a Flutter mobile app for instructors using this design brief. Reuse the theme tokens, widget catalog, and layout patterns described. Wire up the screens in §5 to the instructor backend (TBD) using Riverpod + Dio + go_router."*
