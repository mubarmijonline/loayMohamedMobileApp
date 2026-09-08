# `lib/core/security/` — what this can and cannot do

Read this before changing anything in this directory. The ceiling is stated
here so the next person inherits it rather than discovering it.

## The honest limits

**Android can genuinely block screenshots and screen recording.** `FLAG_SECURE`
on the activity window is enforced by the OS: the screenshot is refused, the
recording plays back black, casts show nothing, and the app-switcher preview is
hidden. This is real prevention.

**iOS cannot block screenshots. Apple exposes no such API.** Anyone claiming a
hard iOS screenshot block is describing the blank-frame trick — which was
tried here, crashed the app on launch, and has been removed. See the note at
the top of `ios/Runner/SecureCanvas.swift` before reaching for it again.

What is actually achievable on iOS, and what is implemented:

1. Detect a screen recording or mirror *after* it starts, and react — playback
   pauses behind an opaque panel.
2. Detect a screenshot *after* it is taken. The image already exists; it cannot
   be recalled. The event is queued and attributed to the student.
3. Cover the window while backgrounded, so the app-switcher card is not a
   frame of the lesson.

**Captured frames on iOS are legible.** That is the honest position. The
watermark is what makes the resulting leak attributable.

**Neither platform stops a second phone pointed at the screen.** A rooted or
jailbroken device defeats all of it — which is why `DeviceIntegrity` refuses
video playback on a compromised device rather than pretending.

Because of all of the above, **the watermark is the layer that actually
matters**. It does not stop a leak; it makes a leak attributable, and that is
what changes behaviour. A watermark that vanishes in fullscreen is decoration.

## Why a hand-rolled method channel and not `screen_protector` / `no_screenshot`

The general rule is to prefer a maintained package. It was not followed here,
deliberately:

- Both native sides were already written in this repo against the
  `app/playback_security` channel. Replacing them with a package would be a
  larger and riskier change than finishing them.
- No single package covers all the iOS layers we need (recording detection
  **plus** screenshot detection **plus** the app-switcher cover). We would end
  up with a package *and* custom native code.
- These packages rename methods between majors, and a wrong call compiles fine
  and protects nothing. Owning both sides of the channel means the contract
  cannot silently drift.

The trade-off is that we own the maintenance. The fix for anything that breaks
lands in `AppDelegate.swift` here, not in a package update. Re-test on every
iOS beta.

## The one rule

Nothing outside this directory talks to the method channel. Everything goes
through `ScreenGuard`. If you find yourself importing `playback_security.dart`
from a feature, that is the bug.

## Capture reporting

There is **no capture-report endpoint** in the verified API contract
(`docs/mobile/API_BRIEF.md` has no such route — §5.5 of the build brief
confirms this is pending backend work). Capture events are therefore queued
locally by `CaptureEventQueue` and never posted. Do not invent an endpoint, and
do not silently drop the events — the queue is the handover point for whenever
the backend adds the route.
