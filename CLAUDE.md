# Context for Claude Code

Everything is called **Ammy** — Home Screen name, Xcode target, scheme, source
folder, and bundle ID `com.local.ammy`. This used to be `AMPresence` /
`com.local.ampresence`. The rename landed on **8 Sept 2026** — committed,
pushed, built and installed — and cost the one re-pairing it was always going to.
Changing the bundle ID makes iOS treat the build as a new app rather than an
upgrade, so the old copy had to be deleted first (otherwise both run and both
push to the relay), and the endpoint, secret, media-library permission and
notification permission were all re-entered.

This paragraph has now been wrong in **both** directions: first written in the
past tense before the work happened, then left in the present tense after it
did. Documented state decays in whichever direction you are not looking.
**Check `git log`, not this file.**

**Don't change the bundle ID again** without wanting that. Nothing displays it,
so there is never a cosmetic reason to.

Apple Music on iPhone → Discord Rich Presence on a Windows desktop.

```
iPhone ──https──▶ <machine>.<tailnet>.ts.net (Tailscale Funnel) ──▶ Issun, 127.0.0.1:8787 ──IPC──▶ Discord desktop
```

The receiver on the main PC is **Issun** (github.com/kaydenpmd/Issun, cloned at
`C:\Users\links\Repos\Issun`), and it is the only one. Don't redesign it — the
shape is deliberate.

**Two retirements, decided 25 Sept 2026, in the owner's words.** "kill relay.py
it's obsolete": `bridge/` (`relay.py`, `install-task.ps1`, `ipc_test.py`) was
deleted from the repo (committed 9 Oct 2026), and Issun has no supported
fallback. The last relay.py stays in git: `git show 3b7875c:bridge/relay.py`.
And "i'm gonna stop using kaydenpmd.net across this entire thing in favor of
tailscale. need to live among the people": the endpoint is Tailscale Funnel
only, and the old Cloudflare tunnel address is retired as an endpoint. The
AltStore source stays where it is — "altstore can stay using my site" — on
`apps.kaydenpmd.net`.

**Leftovers on the PC, unchanged from 9 Oct to 4 Nov 2026.** The old installed
relay (relay.py, its `.env`, `relay.log` and `ammy-uptime.log` in
`C:\Users\links\Python Scripts`) and the disabled `Ammy Relay` logon task were
still there. They are obsolete, not a rollback: never enable the task, which
would contend with Issun for port 8787, and removing them is the owner's call.
The tunnel's service was still running too; see "Funnel is the only endpoint"
under Where things stand. The installed Issun, build 38 through all of that, has
been updated three times since, each time at the owner's yes, with the build it
replaced kept beside it as `Issun.exe.b<build>.bak`: to build 43 on 29 Oct 2026,
with the new icon and a tray hint and new-key notice that no longer name Ammy;
to build 46 on 3 Nov 2026 (`/version` answered `issun 0.1.0 (46)` on 4 Nov);
and to build 48 on 11 Nov 2026, which logs the keepalive journal (see
Diagnostics).
Since 12 Nov 2026 it has been replaced many more times by local publishes of
Issun's unreleased `main` (`tools/install-local.ps1` there), build 142 on
13 Nov 2026 among them. Issun's CLAUDE.md records each update; ask
`/version` for the current one.
Updating stops the live receiver for a few seconds, so get a yes first; the
procedure is in Issun's CLAUDE.md, "Updating the installed copy".

## Why it's built this way

Discord has **no Rich Presence SDK on iOS**. The official path is a local IPC
socket (`\\.\pipe\discord-ipc-0`) that only the desktop client exposes. Setting
presence from a phone directly would mean opening a Gateway WebSocket with a
user token — self-botting, against ToS, accounts get terminated.

The receiver exists to avoid that. The phone never talks to Discord; it POSTs
now-playing JSON to a receiver on the PC, and the receiver uses the sanctioned
IPC path. **Any change that moves Discord communication onto the phone is
wrong.**

Cost of this design: presence requires the PC awake with Discord desktop open.
That's accepted, not a bug to fix.

## What Ammy is, in anything a user reads

The architecture above is what the *receiver* does. It is not what Ammy is, and
the difference is load-bearing in every string a subscriber sees. **Ammy is a
sender**: it reads Apple Music's now-playing state and POSTs it as JSON to an
HTTPS endpoint the user chooses. It is built to pair with **Issun** — the
owner's Windows desktop application (github.com/kaydenpmd/Issun) that completes
the bridge to Discord — and it works with anything else that accepts an HTTPS
POST.

So the landing page in `public/index.html`, `NSAppleMusicUsageDescription` in
`project.yml`, and the app's own UI all stay receiver-agnostic. Naming Discord
in those places states a requirement that does not exist, and it has already
had to be undone once —
18 Sept 2026, after the first listing pitched Discord Rich Presence, a Windows
relay and a Discord application of your own, which is one receiver's setup
rather than a description of this app. The UI has always had this right on
purpose: it says **Endpoint**, not Relay (the status row's name, and until
2 Nov 2026 the header over the URL and Key fields), because whether the
address forwards, renders or files what it receives is none of the app's
business.

The listing's subtitle and description, the README and the landing page's
prose are the owner's to write (3 Nov 2026). Until the owner writes them the
listing has no subtitle and an empty `localizedDescription`, the README is only
the name, and the landing page has just its buttons and the facts it reads from
`source.json`. Don't fill them in.

This file is the other half of the rule. It documents the Discord receiver,
which is genuinely what it is about, and it goes on saying so — the fix is
never to strip accurate Discord information, only to move it from "what Ammy
is" to "what the receiver does".

**The trap that isn't text:** the listing's accent colour was `#5865f2`, which
is Discord's blurple, so the old framing outlived the words that carried it.
Changed to Apple Music red the same day, and on 29 Oct 2026, with the source's
own colour, to system blue (`#007AFF`, Albums' colour): Music had dropped its
red in iOS 27.2, and Ammy's icon had gone black and white. Check the non-prose
surfaces too.

**The icon, since 28 Oct 2026, is an album cover being sent:** Albums' black
tile, a little larger, with two waves leaving it in Albums' greys, fading as
they go. Like the app's own screens, it names no receiver; the waves go out to
whatever is listening. Issun's icon is the other half of the sentence, the same
two waves arriving at a speech bubble. Both are drawn the way Albums' icon is
(`scripts/make_icon.py` here, `tools/make_icon.py` in Issun), black on white
with no accent colour. Ammy's, like Albums', also has a white-on-black dark
version and a tinted one; Issun's `.ico` is the light tile only. There is no
music note on purpose: since iOS 27.2 the Music app's own icon is a dark note
on a light tile. The owner set aside a sumi-e ink note, asking for "a more
vanilla apple style approach like the albums icon", then turned down white
playing bars on a black tile beside a speech bubble with three dots: "ammy's
just represents music, and issun's just represents chat". Our reading of that,
not the owner's words: an icon here shows what the app does for its partner,
not its category. `public/ammy-icon.png`, the listing's icon, is a copy of
`AppIcon.png`, listed as `ammy-icon.png?v=2`: bump the `?v=` whenever the icon
changes, because SideStore keeps a cached icon while its address stays the same
(PUBLISHING.md). Not yet seen on a device.

## Layout

```
project.yml                          XcodeGen spec — no .xcodeproj is committed
.github/workflows/publish-source.yml On push to main: build, GitHub Release, source.json
.github/workflows/build-ipa.yml      Called by the above; unsigned IPA + simulator build
scripts/build_source.py              Regenerates public/source.json
scripts/make_icon.py                 Draws the app icon, like Albums' script of the same name
scripts/measure_marquee.py           Times a scrolling line in a screen recording (Open work item 10)
source.config.json                   AltStore listing metadata (user-facing copy)
public/                              Cloudflare Pages site: landing page, source.json
PUBLISHING.md                        One-time setup for the AltStore source
local/                               Private notes and data, never committed (.git/info/exclude)
Ammy/
  AmmyApp.swift                      SwiftUI entry point + settings screen
  PresenceController.swift           Wires playback changes to pushes; failure announcing
  NowPlayingMonitor.swift            MediaPlayer observation; store ID + cover art
  PresenceRelay.swift                HTTPS client for the endpoint; PushOutcome
  KeepAlive.swift                    Silent audio to survive backgrounding
  KeepAliveJournal.swift             The keepalive's on-disk log; its tail rides the next run's pushes
  Diagnostics.swift                  The phone's self-report, sent with every push
  SilenceWatchdog.swift              Notification for when the app isn't running
  EventLog.swift                     Link history: failures, interruptions, recoveries
  LinkHistoryView.swift              The History screen
```

The receiver's code, settings and logs are Issun's; its CLAUDE.md is the
reference for all three.

## Telling builds apart

Both halves are versioned. Check these before debugging anything.

**Receiver** — `GET /version` on the Funnel address answers
`issun <version> (<build>)`, and the `X-Ammy-Relay` header on every response
carries the same string. Issun's CLAUDE.md covers where else its version shows.
This document deliberately does **not** state the current version — it went
stale within the hour, twice. Ask `/version` instead.

`/health` still returns exactly `ok` and nothing else — Shortcuts test for that
string, which is why the version got its own route.

The other routes, so they are not rediscovered: `POST /now-playing` is the
phone writing, `GET /now-playing` is anything else reading — same path,
opposite directions. `GET` returns a projection, never the raw push, and never
performs a lookup, so a public endpoint can't be used to make this machine
issue outbound traffic. `/diag` is the phone's last self-report, `/status`
answers `alive`/`stale` for Shortcuts, and `/art/<hash>.jpg` is open because
Discord's CDN fetches it and cannot send our header.

**iOS app** — the **Version** row, under Endpoint, shows e.g. `1.0 (7)`. The
build number is the count of commits reachable from the built commit (`git
rev-list --count HEAD` in `build-ipa.yml`), and the artifact is named to match:
`Ammy-1.0-b7-a1b2c3d.ipa`. Matching numbers means the phone is running the build
you think it is. `MARKETING_VERSION` in `project.yml` is the only version number
a human sets; the build number climbs on its own.

## Gotchas already paid for — don't rediscover these

**The large title jumped on collapse because the bar was the Form's. It's the
stack's since 2 Nov 2026.** Scrolling down from the top, the title snapped shut
as the scroll began and the content leapt ahead of the finger, then followed
it. In the owner's recording of 11 Sept 2026 (build 45,
`ScreenRecording_09-11-2026 04-20-52_1.mp4`), each of twelve scrolls down
starts from rest with a jump: eight of 49.5–57 pt in a single frame, about the
whole 52 pt collapse at once, and four of 15–47 pt. The "crawl of 1px per
frame" this entry used to describe after it is the finger itself, dragging
slowly. Measure a jump like this with a search wider than it: a ±90 px one
first read the same frames as 37–45 pt. The simulator gives 52 pt in one frame
on iOS 26.5 and about 34 pt over three frames on 27.0. Expanding was clean.

**Why.** `safeAreaBar` wraps the view it modifies in
`_UIInteractionView<_UIScrollPocketCollectorInteraction, …>`, the view that
collects the scroll edge effect. Between the page and the Form's
`UICollectionView`, that view keeps UIKit's eager update of the collapsing
title's insets
(`-[UIViewController _updateViewSafeAreaInsetsAndEagerlyUpdateContentScrollView:]`)
from reaching the Form, so the new top inset arrives only when SwiftUI's next
render sets the host's geometry (`DisplayList.ViewUpdater` → `setCenter:` →
`setSafeAreaInsets:`). Each late inset re-pins the content offset, which
collapses the title further, which asks for another render: on iOS 26.5, 35
inset updates in one frame from a 0.5 pt finger move. Every API here is the
sanctioned one, so "the code is not wrong" held for each piece but not for the
whole: the combination is a SwiftUI defect, and it has a workaround. No
published report matched it (searched 1 Nov 2026).

**The 11 Sept decision was to leave it** for a future iOS to fix: a workaround
outlives the defect, and every alternative cost something real, the large title
or the scroll edge effect beneath the button. The one below costs neither, and
what it carries is small: a padding on the Form, and a copy of the bar for the
page's slides to History. On 1 Nov 2026 the owner asked for another look: "i
want to really make sure it's not something we can fix cause it's still present
on ios 27".

**How it was found**, so it isn't redone: a lab on the `jitter-lab` branch,
never merged. Ammy's screen with one bottom bar at a time, driven in CI on an
iPhone SE simulator (iOS 26.5 with Xcode 26.6, 27.0 with Xcode 27.2) by
scripted drags, logging every display frame: the content against the finger,
the insets, the navigation bar, and the call stack of every inset change.
Every variant with `safeAreaBar` on the Form jumped: Ammy's bar, a zero-height
bar, a 1 pt one, a 143 pt one (so the inset's height isn't the trigger, which
answers the experiment this entry used to leave untried), a `List`, `.hard`
and hidden edge effects, and partly a `ScrollView`. None without it did; all
stayed within 2.5 pt of the finger: no bar, `safeAreaInset` (build 39's bar
too), `contentMargins` or `safeAreaPadding` with an overlay, a `.bottomBar`
toolbar, and `safeAreaBar` on the `NavigationStack`. The real Ammy, built from
the branch and scrolled the same way on iOS 27.0, agreed: −12, −30, −30 and
−29 px over four frames with the bar on the Form, a steady 5–6 px a frame with
it on the stack.

**A correction: build 39 was `safeAreaInset`, not `safeAreaBar`.** Build
numbers were CI run numbers then. Run 39 built d6516a6, whose bar is a
`safeAreaInset`; the `safeAreaBar` arrived in run 40, 4f200f9. The lab finds
`safeAreaInset` clean, and the earliest recording of the jump is build 45's,
so "it appeared in build 39" was most likely inferred, not seen.

**The fix: the bar belongs to the stack.** `ContentView` attaches the same bar
to the `NavigationStack`, so the effect's collector sits outside the page and
UIKit updates the Form directly. In the simulator it is pixel-identical at
rest to the bar on the Form, edge effect included, at the top of the page
and, since build 158, at its foot, on an SE (26.5 and 27.0) and a Face ID
iPhone 17e (27.0). Two things come with it:
- A stack doesn't pass its bar's inset down to the lists inside it
  (FB23732628, forums thread 837946), so the Form adds the bar's measured
  height to its own safe area, `.safeAreaPadding(.bottom, barHeight)`, as
  the bar did when it was the Form's: 87.5 pt on the SE and 34 + 53.3 on the
  17e. The list keeps its own 20 pt below the last row on top of that, and
  the scroll indicators, which follow the safe area, end at the bar's top.
  Builds 150 to 156 gave the height to `contentMargins` for the content and
  the indicators instead, and a margin there replaces the list's 20 pt
  rather than adding to it: History ended 16 pt above the button. In the
  `header-lab-option1` lab (2 Nov 2026; SE on 26.5 and 27.0, and 27.0 with
  the iOS 26.5 SDK, as CI builds; its report is `lab/REPORT-option1.txt` on
  that branch), History ends 36.0 pt above Start with the
  padding or the bar on the Form and 16.0 with the margins, at XXXL text and
  with the media prompt up as well. The padding doesn't bring the jump back:
  every inset update during a drag took UIKit's direct path, and the content
  never got ahead of the finger. **The 36 isn't seen on a device.** Build
  154's recording (01:34, 2 Nov) shows the margins' 16 on the owner's SE.
  But build 150's page, which ended in the Title Fix switch's footer, ended
  in the same place there with the bar on the Form and on the stack, and no
  lab has tried a page that ends in a footer. Either the room below a footer
  isn't one the margins replace, or iOS 27.2 leaves no room below the last
  group at all, and then build 158 looks like 156 at the foot of the page.
  A screenshot of build 158 there settles it. If a later iOS starts passing
  the inset down, the Form gets that room twice, and the padding goes.
- A stack's bar outlives its pages, so it would sit over History. Since build
  156 the page carries an identical copy of the bar while it slides to History
  and back, from its `viewWillDisappear` to its `viewDidAppear`
  (`PageTransitions`, a view controller in the page; History's `onAppear` and
  `onDisappear` arrive after the slides and stay only as a backstop). The
  stack's bar steps aside without animating, and the copy goes with the page and
  under History, as the bar did when it was the Form's. Fading the stack's bar
  instead was tried twice. Builds 150 and 152 faded it after the slide, from
  History's callbacks: "Stop" lingered over History for about 0.1 s and came
  back about 0.4 s after the page. Build 154 faded it during the slide, from the
  page's transitions, and the owner found that "bottom looks worse now on page
  transitions": a fading glass button is a murky half-transparent capsule, navy
  for the blue Start, over History's rows for about 0.4 s, and the edge effect's
  band then switched off in one frame. In the lab (SE and Face ID simulators,
  iOS 26.5 and 27.0) the copy lands on the stack bar's pixels at both handovers,
  the capsule's edges within 0.02 px; History has neither bar nor band; and a
  swipe back that's called off leaves the page carrying it. Build 158's padding
  sits beneath the copy's overlay, so `header-lab-option1` measured it again:
  the copy exactly on the stack bar's frame at every handover, and the capsule's
  edges within 0.04 px through every slide on iOS 27. iOS 26 still tints the
  strip behind the bar, so there the tint goes as the slide away starts and
  returns once the page has settled back. Not yet seen on a device. The lab's
  recordings carry wall-clock `pts_time` beside a `dts` that drifts behind it,
  and ffmpeg's default timestamps follow the `dts`, so read `pts_time`: the
  default made the History test look unrecorded. The macos-26 runner's recorder
  also drops most frames while anything moves, so time slides on the xcode-27
  runner's.

**Rejected, so not worth retrying:** `safeAreaInset`, or `contentMargins` with
an overlay (no edge effect: rows show crisp behind the button); UIKit's
`UIScrollEdgeElementContainerInteraction` on an empty view behind a
`safeAreaInset` bar (no visible effect in the simulator); a `.bottomBar`
toolbar (the button shrinks to a capsule whatever `.buttonSizing(.flexible)` or
`.frame(maxWidth:)` asks, `.sharedBackgroundVisibility(.hidden)` leaves it
almost invisible, and full-width toolbar buttons have their own hit-area bug,
forums thread 836076).

**Seen on the owner's SE on 2 Nov 2026 (iOS 27.2), and the switch is gone.**
Build 148 still jumped that night: "the vertical scroll bug is still here build
148". Build 150 had a temporary **Title Fix** switch, on for the stack's bar and
off for the Form's, and with it on the owner's verdict was "i think it looks
good now". Their screen recording agrees: the title rises with the content and
the inline title fades in, and the two scrolls down from the top start at no
more than 2.5 pt a frame, where September's leapt up to 57 pt in one. The foot
of the page is the same to the pixel in either position: two screenshots there
differ only in the clock and the switch. That page ended in the switch's footer,
though, and one that ends in a row is another matter (the fix's first bullet,
above). What the recording couldn't show is the other position jumping. Flipping
the switch rebuilt the list, which landed back at the top, and after a flip
neither position jumped, in six scrolls with the bar on the Form and two with it
on the stack. So the evidence is build against build, 148 against 150, and the
next test of this kind should compare launches, not flips. It was also the fix's
first run as CI builds it, with the iOS 26.5 SDK, on iOS 27, a combination the
simulator never covered. The switch went in build 152. A Feedback report is
drafted with a minimal reproduction (`lab/FEEDBACK.md` and `lab/Repro` on the
`jitter-lab` branch) and waits to be filed from the owner's account.

**No section headers on the main screen, since 2 Nov 2026 (build 158).** With
the jump fixed, the owner looked again: "i don't see apple using the Big Title
with Section Headers pattern anywhere". A survey the same day, on the iOS 27.0
and 26.5 simulators (`header-lab-apple`, never merged), Apple's iOS 27 guide
images and the owner's 27.2 screenshots, found them right:
- **Settings never pairs them.** Its top level, the Apple screen most like
  Ammy's (a root of grouped rows under a picture card, titled with the app's
  own name), is a large title over groups that space alone separates. Every
  Settings page with headers has an inline title (Search, Camera, Safari,
  Notifications) or a header card (Accessibility, Screen Time, Wi-Fi).
- **Other apps do, with a bolder kind.** Files' Browse, Notes' Folders,
  Health, Podcasts and Home put headers under a large title, almost always
  bold, in the primary colour, about 20–22 pt, often collapsible or with an
  action. Ammy's were the kind Settings uses on its pages: grey, semibold,
  body size. The one clean match for Ammy's old combination is Passwords'
  root in Apple's iOS 27 guide, a single grey "Shared Groups" below a grid of
  tiles, shown only to people who have shared groups. Contacts, the HIG's old
  example of a large title, is inline on 27.
- **Apple's written guidance doesn't decide it.** The HIG allows a large title
  without requiring one, counts headers as one of three ways to separate
  groups, with footers and space, and says nothing about the pairing.

Two options went to the owner, rendered in the `header-lab-ammy` lab (never
merged): the large title without headers, as on Settings' top level; or the
headers under an inline title, as on Settings' pages, which would also have let
the bar go back on the Form and retired the workaround above, since an inline
title has no collapse to jump (`jitter-lab-inline`, never merged, found it clean
in the simulator). The owner chose "Option 1". Without the Now Playing, Endpoint
and Status headers an SE shows 86.5 pt more when the screen opens, everything
but History above the button, and a 17e fits the whole page at the default text
size, with nothing to scroll. The footer stays under the URL and Key fields, and
"Endpoint" stays as the status row's name. The costs: the URL and Key card has
no title, and VoiceOver lost the "Now Playing" it read before the song card,
until build 164 (next entry). Build 158 also gave History back its room at the
foot of the page, in the simulator at least (the fix's first bullet, above), and
`header-lab-option1` (never merged) checked both before release: no jump, the
copy of the bar on the stack bar's pixels through History's slides, and the
keyboard and the media prompt as in build 156. Not yet seen on a device.

**VoiceOver reads "Now Playing" before the song again, since build 164.** Asked
on 4 Nov 2026 whether it should, the owner picked "Leave it", then wrote "no i
mean have it read it". The words came back as the start of the card's own label,
not as a header: `accessibilityLabel(content:)` straight after the row's
`.accessibilityElement(children: .combine)`, the same pair in the same order as
Apple's sample code for WWDC24 session 10073 (`BeachesView.swift`). The
`a11y-lab-nowplaying` lab (never merged; three runs on 4 Nov 2026, read on 11
Nov; its reports are in `a11ylab/results/` on that branch) read the card with and without it in five states, light and dark, on an SE
(iOS 27.0 and 26.5) and a 17e (27.0), and on both again with the iOS 26.5 SDK,
as CI builds: 50 cases, and in every one the label is "Now Playing", a comma and
a space, then exactly what build 158 reads ("Now Playing, Blue, Joni Mitchell",
"Now Playing, Not Playing", "Now Playing, Not Available"), with no traits, so it
is one stop and no heading, where build 156 stopped on the header first. A long
title is read once and whole, and the explicit E comes through as an attachment
character (U+FFFC), as in 158. Nothing else moved: the same stops in the same
order, no pixel different outside the status bar, the card still 85 pt with the
artwork 14 pt from its edges, and Apple's accessibility audit found the same
single issue in both builds, the disabled Start button's contrast. VoiceOver
itself can't run in CI, so it isn't heard yet.

**The bar went behind the keyboard, from build 77 (18 Sept 2026) to build 172.
Fixed 12 Nov 2026.** The owner noticed that editing the URL or Key mid-session
no longer showed Stop + Restart above the keyboard. The cause was the bar's
bottom padding, `edgeGap - bottomSafeArea`, and the reading behind it: an
`onGeometryChange` outside the bar reads the bottom safe area *with the
keyboard in it*, 260 pt on an SE and 328 on a 17e while the keyboard is up (0
and 34 otherwise). 21 − 260 took the bar down until its button sat 66.5 pt
under the keyboard's top (66.3 on the 17e), not hittable. Build 70
(7adf1c8) had padded `max(0, 16 - inset)`, which clamps to 0 there, so the
bar sat on the keyboard; build 77 (c02919b) dropped the clamp ("no clamp
needed") for the 21 pt edge gap. The move of the bar to the stack in build 150
didn't cause it: in the lab, build 148's arrangement (the bar on the Form)
reads the same 260 and hides the bar the same way. The option-1 lab of 2 Nov
saw it ("Start sits under the keyboard") and passed it as "same as build 156",
which it was.

The fix keeps the bar on the stack and adds a second reading: a `Color.clear`
background with `.ignoresSafeArea(.keyboard)`, outside the bar, whose
`safeAreaInsets.bottom` stays at the home indicator's 0 or 34 while the
keyboard is up. That is `bottomSafeArea` now; the old reading only says whether
the keyboard is up (it reads more than the other). With the keyboard up the bar
pads `edgeGap` above the keyboard's top on every phone, as a home-button phone
always had; otherwise nothing changed. Both readings are logged (category
`bar`). `ignoresSafeArea(.container, edges: .bottom)` on the bar instead, with
a plain `edgeGap`, was tried and is wrong: on the 17e it put the bar 55 pt off
the edge at rest.

Measured in the `keyboard-lab` lab (12 Nov 2026, never merged; run
43177485233, report and screenshots in `lab/results/` on that branch): the
release's build (iOS 26.5 SDK) on an SE and a 17e, iOS 27.0 and 26.5, dark
mode, the URL and Key fields each focused and typed in, with Start alone, Stop
alone and Stop + Restart. With the fix the buttons end exactly 21.0 pt above
the keyboard (Passwords bar included), hittable, on all four, and iOS scrolls a
focused Key field on the SE to end exactly at the bar's top. At rest the fix is
pixel-identical to build 172 (44 pixels on the glass rim of one SE iOS 26.5
capture differ by at most 3 of 255, frames identical), so the page's copy of
the bar for History is unchanged too. The large title's jump stays gone: on
every drag and flick the fix tracks the finger as build 172 does (slow drags
at most 2–6 pt a frame), while the bar-on-the-Form control jumps up to 37.5 pt
in a frame. On the 17e recording the bar rides up with the keyboard with no
visible step where its padding changes by 34 pt. **iOS leaves the keyboard out
of screenshots while the secure Key field is focused**, so a picture of that
case shows a button the keyboard really covers; trust the frames. Not yet seen
on a device, nor on iPad's floating or hardware keyboards.

**16 Sept 2026: iOS 27 removed the tint behind the bar, and Ammy followed for
free.** `safeAreaBar` does not draw a background — it applies the system's scroll
edge effect, which is all Ammy ever asked for. Apple changed what that effect
looks like and Ammy changed with it, in step with Music, without a line moving.
Had the early objection to the hard background been answered by painting one by
hand, Ammy would now be the only app on the phone still wearing the iOS 26 look.
**Do not "fix" the absence of a background by adding one.**

**Measured against Music on a 375pt screen, same day.** Both of Music's bars —
the tab bar and the mini-player — start at x=40 in a 2x screenshot, so **20pt**.
Ammy's button starts at x=43, **21.5pt**. Music draws a bright specular rim at
its boundary (237 falling to ~120 over two pixels) and `.buttonStyle(.glass)`
draws none, so aligning *fills* rather than outer boundaries puts them half a
point apart instead of one and a half. Somewhere between 0.5 and 1.5pt out;
not worth changing on that evidence. Note the tempting fix does not work:
`.padding(.horizontal)` with no argument resolves to SwiftUI's 16pt default,
visibly narrower than either. **The system does not expose the tab bar's inset
anywhere reachable**, which is why this is a measured number with a flag on it.

**Glass button styles are already interactive.** `.buttonStyle(.glassProminent)`
scales, shimmers and lights up at the touch point on its own — verified on
device, build 42. Do not add `.glassEffect(.regular.interactive())` on top; that
stacks a second material on a style that already has one. The public write-ups
contradict each other on this, and an afternoon went into reasoning about it
before one install settled it in two seconds. **When a question is about how
something feels on the device, build it and touch it** — that is the cheaper
instrument, and this project has now paid for that lesson twice.

Related, and separate: elements *melting into each other* is a different effect,
and it needs a `GlassEffectContainer` with more than one glass element. The
bottom bar has one: Stop (`.glass`) and Start/Restart (`.glassProminent`) sit in
a `GlassEffectContainer` and morph through `glassEffectID` when editing the
endpoint mid-session splits the bar into Stop + Restart, and again when it
rejoins. The container does the merging; an extra `.glassEffect` on either
button adds nothing. A lone button has nothing to merge with. Conflating the two
effects is what sent this the wrong way.

**Silent failure is this project's recurring bug.** Three separate times, a
function returned `None` on a failure path without logging, and the empty log
read as "working" rather than "broken." Every artwork path in the receiver
logs on failure. **When adding a new failure path, log it** — an unexplained
silence costs days here.

**The Discord-side lessons live in Issun's CLAUDE.md**, under "relay.py's
gotchas, preserved, and where they live now", with the code that carries each
one: the playhead anchor paired with the push's arrival time and never the
clock (the project's most expensive bug, the rubberbanding progress bar); a
rejected payload is not a dead socket, and Discord's two-character minimum
("i" by Kendrick Lamar); pypresence's enums and `push_with_fallback`'s quoted
field names, which Issun's own IPC client made unnecessary; and the
interactive session Discord's pipe needs. They were relay.py's lessons and are
Issun's code now, so that is where to read and change them.

**currentPlaybackTime is unreliable right after a track change.** It can report
the previous song's position for a second or two. `PresenceController` re-reads
elapsed at send time (not from the Combine-captured snapshot) and fires a
correction push 2.5s after every change. Removing that correction reintroduces
wrong progress bars on skip.

**Live stations have no position, and it used to crash the app.** On Apple
Music 1, `nowPlayingItem` is the song the station is playing, with its real
title, artist, store ID and length, but `currentPlaybackTime` is NaN.
`JSONSerialization` can't write NaN, and it raises an Objective-C exception
instead of throwing, so the `try?` around it never got a chance and Ammy died
whenever a station played. Fixed 23 Sept 2026 in builds 86 and 88:
- `NowPlayingMonitor` treats a non-finite position as live: it sends
  `duration: 0` (receivers already read that as "no progress bar") and
  `live: true`.
- `PresenceRelay` checks `isValidJSONObject` before encoding.

Sending the real length with the position stuck at 0 was tried in between, and
it's worse: every heartbeat says "0 seconds in", and the bar snaps back to the
start every 30 s. On Discord a station now shows the song and cover with a
small "♫ 0:42"-style counter. That counter is Discord's own, drawn for
activities with no timestamps, and nothing sent over RPC removes it.

**KeepAlive must survive interruptions — and `.ended` is not guaranteed.** The
silent audio holds the app alive only while its `AVAudioSession` is active. Four
separate things stop it: an interruption (call, alarm, Siri), a media services
reset, an `AVAudioEngineConfigurationChange` when the audio route switches
(AirPods, headphones, CarPlay), and a `resume()` that simply fails. All four are
handled; before September 2026 only the first two were, and the app died
silently for 39 hours straight (Aug 27–29).

The rule that matters is **never conclude the keepalive is off.** `running`
means "we want silence playing"; a failure leaves it true and lets a 10-second
timer retry. The old `start()` returned early on a failed `resume()` with
`running` still false, so the observers were never installed and nothing ever
retried — the app then ran with no keepalive at all and nothing anywhere said so.

**Recovery must not depend on `.ended` alone.** iOS does not reliably deliver
the `.ended` half of an interruption, particularly when it finishes while the
app is suspended. This is not theoretical: the first instrumented build reported
`int=3/2` — three interruptions began, two ended. Under the old code the engine
would have stayed stopped from that moment onward. `.began` and `.ended` are
counted separately precisely so that mismatch is visible.

Diagnosis note from Sept 2026: every death recorded on build 25 carried
`engine=yes want=yes`. The audio engine was alive at the moment the app stopped
checking in, every time — so a dead keepalive was *not* the cause of the deaths
that remained, and `config_changes` was 0 across five route changes. The fix
that demonstrably paid off was the retry-and-recheck loop, not the
configuration-change observer. Don't remove either on the strength of that;
`resume_failures` and `self_heals` both fired and both recovered.

**Notification permission is not optional.** `UNUserNotificationCenter.add()`
on an unauthorized center succeeds and delivers nothing — no error, no crash.
`SilenceWatchdog` was inert for its entire existence because nothing ever
called `requestAuthorization`. `PresenceController.start()` now does, before
scheduling anything.

**The silence warning is inverted on purpose.** `SilenceWatchdog` schedules a
notification 15 minutes out and re-schedules on every successful push, so it
never fires while Ammy is alive. A dead app can't notify you; a living one can
leave a note that goes off if it stops. Pending notifications live in iOS's
notification daemon, so this survives force quit, eviction and reboot. Don't
"fix" it by detecting death directly — there's nothing left running to detect
it with.

**No .xcodeproj in the repo.** CI generates it with XcodeGen from
`project.yml`. `SWIFT_VERSION` is a *language mode* — valid values are
4.0/4.2/5.0/6.0. "5.9" is rejected.

**Don't transcribe config from screenshots.** The Discord client ID was once
copied from a screenshot with one digit misread, and Discord answered
`Error Code: 4000 Message: Client ID is Invalid` — which reads like a deleted
application, not a typo. Paste values rather than retyping them, and print
`.Length` rather than the value when checking a secret.

## Diagnostics

The receiver writes these lines, and Issun keeps relay.py's wording for them
word for word (even "relay up throughout"), because the history and its summary
parser depend on it. Issun's log is `%LOCALAPPDATA%\Issun\issun.log`, its
check-in history is `%LOCALAPPDATA%\Issun\uptime.log` (relay.py's history merged
in ahead of its own), and its window's Diagnostics section shows the summary
that `python relay.py --summary` used to print. **Read them from PowerShell, not
Claude Code's Bash shell**, which is sandboxed: on 11 Nov 2026 it still showed
an `issun.log` of 38 lines from 22 Sept, while PowerShell showed the real one,
6,164 lines and current (Issun's CLAUDE.md has the same warning).

**The app cannot report its own death.** By the time anyone notices it is gone
there is nothing left running to ask, and the receiver only ever sees that
pushes stopped — never why. So every push carries a `diag` snapshot of the
phone's condition, the receiver keeps the most recent one, and
`UptimeLog.NoteSilence` prints it onto the "phone stopped checking in" line.
That last snapshot is the entire account of what preceded a silence.

```
phone stopped checking in  last seen 00:39:33  last state: engine=yes want=yes
route=BluetoothA2DPOutput resumes=1 fails=0 heals=0 cfg=0 routechg=1 int=0/0
mem=19MB state=background lpm=no thermal=fair appup=3554s devup=31067s
```

How to read it:

- `engine` is `AVAudioEngine.isRunning`; `want` is what `KeepAlive` believes.
  **They disagree only when the keepalive is dead and the app is on borrowed
  time.** Agreeing means look elsewhere.
- `int=began/ended` — began outrunning ended is a missed `.ended`, see above.
- `appup` is seconds since the app launched, so on a death line it *is* that
  instance's lifetime. `devup` dates the last reboot, which turned a remembered
  claim about a phone restart into a checkable one.
- **`appup` can legitimately exceed `devup`, and it is not corruption.** They are
  different clocks: `appup` is `Date().timeIntervalSince(launchedAt)`, wall time,
  while `devup` is `ProcessInfo.systemUptime`, which on Darwin *stops while the
  device sleeps*. An app that lives through a few nights accrues more wall time
  than the phone accrues awake time. Observed 101525s against 80445s on
  16 Sept — six hours of the phone asleep, nothing wrong. Worth knowing before
  distrusting a log, because every death verdict rests on `appup`.
- `mem` is `phys_footprint`, the number jetsam actually measures — not
  `resident_size`, which reads high and matches nothing. Observed 16–25MB.
- `thermal` was added on spec with no theory behind it and immediately became
  the most interesting unexplained signal: it flaps to `serious` repeatedly.
  When you are debugging blind, record everything cheap; you cannot correlate a
  signal you did not keep.

`[keepalive]` lines in the receiver's log record changes as they happen, so the log
shows the *sequence* leading to a death rather than only the state at the end of
it. `GET /diag` returns the latest snapshot on demand, authenticated.

**Since build 167 the phone also keeps its own record** (`KeepAliveJournal`),
for what happens after the last push that got through, which nothing else can
see. Every keepalive event (start, stop, `verify` finding the engine down, each
failed try, each recovery, interruptions with their reason and whether iOS
delivered them late, configuration changes, media resets) is appended to
`keepalive.log` in Ammy's Application Support folder, 400 lines kept, each run
starting with a header line. Every 10 s tick overwrites `keepalive.alive` with
the time and the engine's state, so the last stamp a suspended or killed process
left says when it stopped running, to within one tick. The next launch sends the
previous run's last 25 lines as `prev_tail` and its stamp as `prev_alive` on
every push until one lands. New `diag` fields beside them: `fail_stage` and
`fail_code` (the step of `resume()` that failed last and its error code, kept
after a recovery), `fail_run` and `fail_run_max`, `down_s`, `secs_since_fail`,
`int_on_resume` (late `.began` notices, each proof of a suspension),
`int_reason`, `secs_since_began` and `secs_since_ended`. `last_error` now ends
with the code and its four characters, e.g. `[2003329396 'what']`, so Issun's
existing "resume failed:" lines carry it. **Issun prints the rest from its
build 48** (11 Nov 2026). The first push from a new process that carries the
previous run's account puts it in `issun.log` once, in local time: `[keepalive]
previous run last ran <stamp> engine=yes|no; its journal's last 25 lines
follow`, then one `[keepalive] journal: ...` line each. A gap that ends in a
relaunch says when the dead process last ran (`— it died, last ran 18:52:10
engine=no`). The other fields go on the death line and the window's
Diagnostics line beside the counts they explain (`failrun=`, `failstage=`,
`failcode=`, `sincefail=` and `down=` after `fails=`; `intlate=`,
`intreason=`, `sincebegan=` and `sinceended=` after `int=`), and
`int_on_resume` and `int_reason` are logged as they change. Issun's CLAUDE.md
has the details. Both are on the owner's devices since 11 Nov 2026: Ammy 167
from 18:50:38, the first launch with a journal, so it had no earlier run to
report, and Issun 48 from 18:56:22, whose first report from the phone already
carried `failrun=0/0` and `intlate=0`. The first `[keepalive] previous run`
lines come with Ammy's next launch.

### Was it killed, or just unreachable?

Two different bugs with two different fixes, and until relay 1.8.0 the log could
not tell them apart. A push that fails never arrives, so from the receiver's side
"iOS evicted the app" and "the app was alive and could not reach me" are the
same observation: silence. The evidence has to survive the outage and come back
with the first push that gets through.

Two fields carry it, from opposite directions:

- `app_uptime_s` resets when the process does. The receiver keeps the value from
  the push *before* the gap and compares. Advanced by roughly the length of the
  gap → one process ran straight through it. Went backwards, or forwards by far
  less than the gap → a different process is talking now.
- `pushfail=consecutive/total`, with `offline=Ns`. An app that spent the silence
  failing to send knows it was alive, and says so on its first push back.

The verdict lands on the gap line:

```
gap 00:44:22  phone silent, relay up throughout, app stayed up 6554s -> 9216s —
the path failed, not the app, 88 pushes failed over 00:44:10
```

**Both are needed.** Uptime alone cannot separate a relaunch that happened
immediately from one that happened at the end of the gap. Push failures alone
cannot prove the app did not die shortly after recording them. They agree, or
the verdict is worth distrusting.

A death line always shows `pushfail=0` and no `offline`, and that is not a bug —
the last push to arrive is by definition one that worked. `offline` is omitted
entirely while healthy, so seeing it at all is itself the signal.

This matters more since the move to Tailscale Funnel than it did before. The PC
has to be awake and the tunnel up for a push to land, so "unreachable" is now a
routine event rather than a theoretical one, and two of the September stops
recorded `state=active` — an app being evicted in the *foreground* fits nothing,
and network loss fits it exactly.

A relaunch also gets its own `[keepalive]` line. It used to slip by in silence:
a relaunch resets every counter at once, and only increases were logged.

Builds that predate `diag` are unaffected and simply record nothing.

**The worked example, from 18 Sept 2026.** Three gaps in the whole log record how
many pushes failed first, and they fall either side of one commit:

```
build 45   4 pushes failed over 00:02:36  ->  gap 2m 37s
build 51   1 pushes failed over 03:32:44  ->  gap 3h 32m
build 51   1 pushes failed over 01:30:15  ->  gap 1h 30m
```

One failed push, then hours of nothing, with `app stayed up` and uptime climbing
straight through both (10169→22933, 78568→83984). Not eviction, not memory, not
the watchdog — the app was alive and had stopped trying. That is
teardown-on-first-failure, introduced in `ac2cf68` and fixed by the retry window
in `6746c8c`. Build 45 hit a blip four times over two and a half minutes and
recovered by itself; build 51 hit one and gave up permanently. **This is the
reason the established/never-connected distinction exists** — and the log is what
found it, which is the whole argument for keeping `pushfail` on every push.

**One wrong line in the history, from a relay.py bug Issun fixed.** The 14:59
gap on 14 Sept is logged *twice*, identically, and reads `app restarted 3358s ->
3359s — it died`. Uptime went *up* by a second, which is not a restart.
relay.py's `_gap_verdict()` compared against a `_prev_app_uptime` that a
near-simultaneous second push — the `handleChange()` correction, most likely —
had already advanced, so the delta was tiny against a 38-minute gap and the
second branch fired. One of the fourteen death verdicts in the log is therefore
both double-counted and wrong. Issun's `CheckinProcessor` holds one lock around
the whole check-in, so the second push sees the first as its previous check-in
and writes nothing. The wrong line stays in the imported history; discount it.

Issun has written one of its own. On 8 Nov 2026 at 16:11:50 it logged `gap
00:02:13 ... app restarted 6211s -> 6242s — it died`, but uptime went *up*, and
Issun's own tracker logged no `[keepalive] app restarted` line, as it does for a
real relaunch. A process started during a 133-second gap can't report 6242 s of
uptime. The launch times the pushes imply say what happened: 14:26:06 before the
gap and at 18:46 that evening, but 14:27:48 for the push that ended the gap. So
that push carried a snapshot about 100 s old, most likely built before iOS froze
the app and sent when it woke. Discount that line too: build 158 died nine
times, not ten. The census of 11 Nov 2026 found a third: 16 Oct 2026 at
21:56:52, `89081s -> 89165s`, uptime up 84 s over a 93-second gap. Issun's
build 48 stops writing these: a process whose uptime is more than the gap plus
20 s was running before the gap began, so it stayed up, however little its
uptime gained.

## Artwork

Resolution order, best first:

1. **Catalog ID from the phone** (`store_id` ← `playbackStoreID`) — exact
   lookup, no guessing. This is the normal path.
2. **JPEG uploaded by the phone** (`artwork_b64`) — exact, for tracks with no
   catalog ID. Needs a public base URL, which Issun takes from Tailscale unless
   its Settings override it; the receiver caches the JPEG under a hash of the
   track and serves it at `/art/<hash>.jpg`.
3. **Fuzzy iTunes Search** — best effort, and the source of most historical
   grief.

**History worth knowing.** For most of this project's life the iOS `Track`
struct carried neither `playbackStoreID` nor cover art, so paths 1 and 2 were
unreachable dead code and *every* track went through fuzzy search. Tracks
missing from the iTunes Store search index — common for independent and recent
releases — got no cover at all, and others got confidently wrong ones (a Wiz
Khalifa single matched to *Rolling Papers 2* at 0.48). Fixed September 2026 by
sending both fields from `NowPlayingMonitor`.

**iOS doesn't always have the cover, even for a catalog song.** For songs
streamed from Apple Music, `MPMediaItemArtwork.image(at:)` can return nil though
the artwork object exists, "especially when loading an artwork for the first
time" (Apple Developer Forums thread 743898, no Apple reply). Seen 24 Sept 2026
on "Handle (feat. Don Toliver)": an empty square in Ammy, a cover on the Lock
Screen (which gets it another way), and covers for the rest of the album.
`NowPlayingMonitor` now tries the artwork's own `bounds` size, then asks
**iTunes Lookup by store ID** from the phone, the same exact lookup Issun
makes, with the device region as `country`. It runs once per track, backs
off 60 s after a failure, and drops the answer if the song changed meanwhile.
It's the only request Ammy makes to anything but the user's endpoint.

**The phone sends the JPEG once per track, not per heartbeat** — it's ~80 KB
and the heartbeat is every 30s. The receiver reuses the file already on disk
(`ArtworkResolver.ExistingUploaded` in Issun), without which the cover would
appear on the first push and vanish on the next.

**An `[art] weak match` line now means the phone didn't send a store ID** for
that track. With the ID present the fuzzy path never runs, so those lines have
become a signal about the iOS side rather than about Apple's search index.

The fuzzy floor is **0.35** (Issun's `ArtMinScore`, locked there by the owner on
23 Sept 2026).

## The explicit badge

Added 23 Sept 2026. The Now Playing row puts Music's "E" (`e.square.fill`)
after an explicit track, and the push carries `explicit: true`. It sits inline
in the title's `Text` with `.imageScale(.small)` (`NowPlayingRow.lines`). From
build 120 to 1 Nov 2026 there was a second copy, a text attachment on UIKit's
marquee path, which went with that path (see Scrolling, under the Now Playing
row's proportions). **It's just the symbol after a space, in the title's own
colour**, by the owner's choice on 24 Sept 2026. It matches the Lock Screen and
Control Center player, where the E is opaque, not the Music app, where it's
translucent. The first version dimmed it with `.secondary` and added a
VoiceOver label override; the owner asked for anything more complicated than
the plain symbol to be rolled back, and it was. Issun does the same with a
typed U+1F174.

**At small symbol scale.** On the owner's Lock Screen and Control Center
screenshots, Apple's E is exactly cap height, top on the cap line and bottom on
the baseline. Build 101's, at the default medium scale, was 1.29× cap height
and overhung both. The HIG's SF Symbols page defines the three scales "relative
to the cap height", and its figure shows small touching both lines. Whether
`.imageScale` reaches a symbol embedded in `Text` is undocumented, so check it
on a device; since 1 Nov 2026 this is the only path.

**Only ever `true`**: `MPMediaItem.isExplicitItem` is a plain
Bool, and its `false` covers an unrated track as well as a clean one, so the
phone can't honestly claim "clean". Receivers treat an absent flag as "don't
know"; Issun then asks the exact store-ID lookup's `trackExplicitness`, never
fuzzy search. `PresenceController` compares `explicit` beside `Track.key` so a
switch between a song's clean and explicit editions, which share title, artist
and album, pushes at once rather than at the next heartbeat. The Now Playing
row's `song` does the same, so on that switch the title and artist start again
from rest, as for a new song, rather than jumping partway through a scroll when
the E changes the title's width.

**Not yet seen on a device.** Whether `isExplicitItem` is populated for catalog
tracks streamed through `systemMusicPlayer`, rather than only for library items,
is undocumented. If the phone never shows the E on a song Music marks explicit,
that is the answer — and Issun's window would still show it, from the lookup.

Discord's activity object has no field for explicitness, so Issun leaves the
card as it was; the badge is its window's and `GET /now-playing`'s.

## The Now Playing row's proportions

Matched to the Lock Screen's Now Playing card on 24 Sept 2026, from the owner's
SE screenshots and Apple's documentation. The code comments say which is which.
The short version:

- **Artwork 57 pt, a constant, because the Lock Screen's is one.** The owner
  asked (29 Oct 2026) for the size to come from "whatever logic makes it the
  size that it is" rather than from a measurement. There is no logic: Apple's
  Lock Screen player sets the artwork's frame to a literal 57.0 x 57.0 pt
  (`-[MRULockscreenView layoutSubviews]` in MediaControls.framework, in the
  decompiled iOS 17.6.1 build at github.com/SuperChaoM/iPhone15-3_17.6.1_21G101_Restore;
  the same structure in decompiled 18.2 and 26.1 builds). Nothing there reads
  Dynamic Type, the screen width or the device. The owner's SE screenshots on
  iOS 27.2 agree: 57.0 pt at both the smallest and the largest standard text
  size, while the title grew (cap height 9.5 to 13 pt). So a fixed 57 is the
  Lock Screen's own rule, on every iPhone and at every text size, and under
  Display Zoom both scale together, being points. Apple documents none of it,
  and a later iOS could change the literal: re-measure after a major release.
  The same code's other numbers, for reference: 14 pt insets on every side
  (also the HIG's documented Lock Screen margin for Live Activities), a 12 pt
  gap to the text, a fixed 7.5 pt artwork corner, and text capped at Dynamic
  Type XL. Its corner is concentric only because its inset is fixed too; the
  row computes its own from the artwork's measured gaps (see Concentric corner).
- **Title and artist the same size**, one line each, scrolling when too long:
  Headline and Body, both 17 pt per the HIG's type table. The Lock Screen
  measures 17/17, and the UI kit gives Control Center 14/14.
- **Lock Screen spacing, since 31 Oct 2026**: 14 pt from the artwork to the
  section's side, top and bottom, and 12 pt from the artwork to the text, the
  Lock Screen player's own constants (see Artwork 57 pt), on every iPhone. A
  List won't give a row those numbers directly, so the row pads by the
  difference from the list's own insets, which are measured: the side from
  where the list put the row against its cell, and the top as half the cell's
  height beyond the row's, read only once both have stopped changing for
  150 ms. The padding is negative where the list's insets are wider: on the
  owner's SE on iOS 27.2 the list gives 20 at the side and 15 at the top, so
  -6 and -1. Verified on the owner's SE: a screen recording of build 141
  measured the artwork exactly 14 pt from the side, top and bottom, in an
  85 pt card, the same on every flip of the then-temporary switch.
- **Why padding and not `listRowInsets`**: on 29 Oct, build 134 asked for zero
  vertical insets with `listRowInsets(.vertical, 0)` and added 20 pt of
  padding, and the owner's SE showed 35 pt above and below the artwork: the
  list's own 15 plus the 20. **A zero vertical `listRowInsets` had no effect on
  this row.** Whether other values do isn't known: after 27.2, builds that
  asked for 16 measured 15 to 16 from top and bottom. Don't rely on them
  without checking on a device.
- **Why the top is read only once things settle**: the two heights come from
  different views (the row and its `listRowBackground`) at different moments,
  so mid-change their difference is wrong, and a wrong value moves the
  padding. Build 139 read it at every change, but only while the switch was
  off, and the owner's recording (31 Oct 2026) showed a reading taken
  mid-change (14 instead of 15) sticking on every other flip on: the card
  stayed 87 pt instead of 85 and everything below jumped 2 pt on alternate
  flips only. Build 141 reads it with the switch in either position and waits
  for 150 ms of stillness, and its recording shows every flip identical.
- **How the owner chose it, so it isn't redone.** On 24 Sept the top and bottom
  were set equal to the side to match the Lock Screen, with the text 14 pt
  along. iOS 27.2 then widened the list's side margin: on the owner's SE 16 pt
  in a 26 Sept screenshot (iOS 27.0, the owner thinks) and 20 on 27.2, where
  everything inside the cards moved 4 pt in, the section headers it had then and
  the Endpoint rows too, while the cards stayed 16 pt from the screen's edge;
  Settings shows the same. Settings' Apple Account row measures a 60 pt picture
  20 pt from the side and 15 from the top and bottom on 27.2, with the name
  about 9 pt after it. On 29 Oct the owner first said "lock screen player has
  its own standard. all i want to copy from it is the fact that its corners are
  concentric. in-app clearly needs much wider margins than this", then chose the
  system's own gaps (build 137), suspecting 27.2's spacing was Apple's mistake
  and matching it anyway: "wanna match here for better or worse / and if they
  fix it in a future update it should make ammy look better". Then they asked
  for the Lock Screen's margins "from first principles" behind a temporary
  switch (builds 139 and 141), compared the two on the device, and chose the
  Lock Screen's: "i do like the lock screen spacing vastly more". The switch was
  removed on 31 Oct 2026. So the artwork's size, the type, the fitted covers and
  now the spacing all come from the Lock Screen; the corner rule is the row's
  own.
- **Concentric corner, as close as the gaps allow**: the section's radius
  (26 pt, measured on two phones; no API) less the average of the artwork's
  measured side and top gaps, never below 6. With equal gaps that is exactly
  concentric, Apple's rule; with unequal ones no radius is, and this one puts
  the artwork corner's centre nearest the section corner's. With the Lock
  Screen's 14 and 14 it's 12 pt. (It was 10 pt with 16 and 16, 6 once iOS 27.2
  made the side 20, which the owner noticed, and 8.5 with the system's 20 and
  15.) Both gaps are measured at run time: the side from the artwork's leading
  edge against its cell's, the top from the cell's height, which scrolling
  can't change; a side outside 8–40 pt or a top outside 4–60 pt is ignored. If
  the text outgrows the artwork at the largest text sizes, the artwork sits
  centred lower and the corner follows. The section radius measured the same
  after 27.2. A List cell doesn't give ConcentricRectangle a container shape
  (developer forums thread 798726), so it's done by hand. The owner asked to
  keep this "so it can do its best to match".
- **Other iPhones**: the corner and the pixel size of the artwork follow the
  device, and the gaps are the Lock Screen's on every one, reached by
  measuring each device's list. The 57 pt artwork is constant by Apple's own
  code (above); the 26 pt section radius is believed constant, confirmed on an
  SE and a Pro Max.
- **Soft artwork**: downsampled with ImageIO to the exact pixels drawn, WWDC18
  session 219's documented method, instead of Core Animation shrinking a 512 px
  cover on the fly. What filter the Lock Screen itself uses is not documented.
- **Non-square covers are fitted, not cropped**, centred in the 57 pt square
  and rounded at their own corners, as the Lock Screen draws them (a portrait
  cover measured 49 × 57 pt there).
- **Nothing playing**: a plain `tertiarySystemFill` square, no symbol, no
  hairline. Control Center's is an empty translucent square (Apple's iPhone
  User Guide screenshot); Apple names no colour, and tertiarySystemFill is the
  documented fill "for large shapes".
- **Scrolling is Music's own, from Apple's code and measured, since 1 Nov
  2026** (Open work item 10 has both). `MarqueeLine` is a plain marquee,
  holding 3 s and then scrolling at 30 pt/s until the line's repeat has taken
  its place, whose whole loop runs through ease-in-ease-out
  (`UnitCurve.easeInOut`, Core Animation's (0.42, 0, 0.58, 1)). So the hold
  stretches to about 4 s, longer for a longer line (4.2 s for one that barely
  overflows the row on an SE, 3.9 s under Display Zoom, 5.8 s with 600 pt to
  travel), and the scroll sets off briskly, is fastest (52 pt/s) at the
  middle of the loop, and eases into the stop as the loop ends. The repeat
  follows 32 pt after the text,
  and both edges fade over 20 pt, the leading one only over the copy that's
  leaving, so the line's start is never faded, at rest or easing into place.
  Since build 148 the title and artist share one loop, as Music's do: both
  start when the song changes, the loop is as long as the line that travels
  farther needs, and the shorter line, moving at the same pace, stops where
  it runs out (`MarqueeLine.Travel`, a preference the row reads). Stopped in
  the background, off under Reduce Motion, where a long line truncates. From
  build 120 until build 145 the row was set to use UIKit's private UILabel
  marquee through LNSystemMarqueeLabel, falling back to a linear
  `MarqueeLine` where iOS lacked it. Which one ran was never confirmed, and
  it doesn't matter: both were linear (UIKit's by Apple's code; item 10), and
  the owner saw "no easing visible". It went, with the package and
  `ThirdPartyNotices.txt`, in build 145, as promised. **Build 148 not yet
  seen on a device.**

## Clickable presence

Discord supports hyperlinking activity text and artwork, and Issun sends all
three (its `DetailsUrl`, `StateUrl` and `LargeUrl`):

| Field | Opens from | Source |
|---|---|---|
| `details_url` | the title line | `trackViewUrl` |
| `state_url` | the artist line | `artistViewUrl` |
| `large_url` | the cover art | `collectionViewUrl`, with `?i=` stripped |

`collectionViewUrl` arrives carrying `?i=<trackId>`, which opens the album with
the current song selected — the same destination `details_url` already provides.
`PyUrl.AlbumUrl` in Issun (relay.py's `_album_url()`) drops that one parameter
and leaves the rest of the query alone,
so the two links mean different things: title goes to the song, cover goes to
the album.

All three come out of the same iTunes lookup that fetches artwork, so links
cost no extra requests. They are populated **only from the exact store-ID
lookup, never from fuzzy matching** — a near-miss cover is a cosmetic
annoyance, but a link that opens the wrong song is a broken promise.

Album name is `large_text`, which Discord renders as *both* the cover tooltip
and a visible third line on the card — one field, two places, and they can't be
separated. Issun never sends it: the owner locked the album line off on
23 Sept 2026, and Issun's CLAUDE.md says where. Spotify's presence shows a
tooltip with no third line, but that's a first-party card Discord special-cases
(it also carries a "Play on Spotify" button); third-party RPC gets the generic
renderer and doesn't get to choose.

## Build and deploy

Push to `main` triggers `.github/workflows/publish-source.yml`, unless the push
touches only `**.md`, `public/**`, `scripts/**` or `source.config.json` (its
`paths-ignore`). That workflow calls `build-ipa.yml`
on a `macos-26` runner, which reads `MARKETING_VERSION` out of `project.yml`,
sets `CURRENT_PROJECT_VERSION` to `git rev-list --count HEAD` (a commit count,
not `github.run_number`; the comment in `build-ipa.yml` says why), builds
unsigned (SideStore re-signs at install), and uploads
`Ammy-<version>-b<build>-<sha>` plus a simulator build for Appetize. The publish
job then cuts a GitHub Release tagged `v<version>-b<build>`, regenerates
`public/source.json` with `scripts/build_source.py`, and commits it back to
`main`, which Cloudflare Pages deploys to `apps.kaydenpmd.net`. To build without
releasing, run `build-ipa.yml` by hand (`workflow_dispatch`). **Pushing to main
is releasing**: the newest commit's message, minus trailers, becomes the release
notes and What's New in SideStore, and earlier commits in the same push don't
appear. `PUBLISHING.md` has the rest.

The source also lists **Albums** since 25 Oct 2026. Albums' own CI pushes
`public/source.json` here with a deploy key, so `main` can move under you
from that side too; `PUBLISHING.md`'s "Albums is in this source too" says how.

Repo is public — macOS runner minutes bill at 10× on private repos.

**A paid Apple Developer account changes the expiry from 7 days to 365**, and
removes the free tier's three-active-apps cap. SideStore's own FAQ states both.
$99/year, and it is the single cheapest quality-of-life fix available — but it
only helps whoever owns the account. It does nothing for anyone else installing
the IPA.

Install path is **SideStore**, not AltStore. AltStore's AltServer requires
iTunes *and* iCloud direct from Apple; the owner keeps the Microsoft Store
Apple apps, and harvesting the 2020 iCloud components produced "The provided
anisette data is invalid." SideStore needs only iTunes (Store version is fine)
and refreshes on-device, so it doesn't hit that wall. Recommend SideStore; the
source also works in AltStore for anyone who already has it, but nobody is told
to go and get it (`PUBLISHING.md` says the same).

## The receiver on the PC

**Issun**, installed at `%LOCALAPPDATA%\Programs\Issun\Issun.exe` since
22 Sept 2026 and started in the tray from the HKCU Run key. It took over
relay.py's port, key and Funnel, so Ammy needed no changes, and since 25 Sept
2026 there is nothing to roll back to. Its settings, the key included, live in
`%APPDATA%\Issun\settings.json`. Issun's CLAUDE.md covers settings, autostart,
updating the installed copy, and the live test of the handover.

What the app's side needs to know:

- **The key** is Issun's, made on first run or by its **New key** button, and
  must match the app's **Key** field. `X-Relay-Key` is the header;
  `X-Relay-Secret`, the old name, is still accepted, so an older build of the
  app keeps working.
- **Ammy says what follows "Listening to", since 14 Nov 2026.** Every push
  carries `"activity_name": "Apple Music"` (`PresenceRelay.push()`), fixed in
  the code and changeable nowhere in the UI, the owner's choice: "update ammy
  to send "Apple Music" for that field. also do not let that be changed
  anywhere in ammy's ui". Issun sends it to Discord as the activity's name,
  which replaces the application's on the card ("Listening to Apple Music").
  It names the player Ammy reads, not a receiver, so the receiver-agnostic
  rule holds. The same day Issun built in one Discord application ID for
  everyone (the owner's own), with no field to change it, so nobody makes a
  Discord application any more; the application's own name now shows only
  when a source sends no `activity_name`, and the owner meant to rename it
  from `Apple Music` to `Issun`. Issun's CLAUDE.md, "The Discord application
  and "Listening to"", has the rest, including the test that showed a name
  sent over the pipe replacing the application's.
- **Public read** (Issun's `PublicRead` setting) serves `GET /now-playing` with
  no key and with CORS, so a web page can read the feed directly. Off by
  default, and a separate switch on purpose: it publishes what you are
  listening to at a URL anyone holding the link can poll. A key cannot be the
  answer there, because a public page would have to embed it.
- **127.0.0.1 only**; Funnel is meant to be the sole ingress (see "Funnel is the
  only endpoint" for the old tunnel still running). `/art/` is deliberately
  unauthenticated — Discord's CDN can't send the key header — and filenames are
  hashes, so they aren't enumerable.

**Why the receiver logs gaps.** Gap logging exists to answer whether iOS
actually kills the app in the background. Gaps are classified as phone-silent
versus receiver-was-down so a PC reboot isn't miscounted as the app dying.

Two halves record it, and both are needed. The check-in path writes the gap when
a push *arrives*, so it can only measure a silence that ended — a death you
never noticed would never have been written down at all. `NoteSilence` is the
other half: the presence worker watches the clock and logs the moment check-ins
stop. It works whether or not music was playing, because every push counts as a
check-in, `playing: false` ones included — a paused app keeps checking in, a
dead one doesn't. The summary reports silences that never got a matching return
as "app died and stayed dead".

On the phone, `SilenceWatchdog` is the third leg: it tells you *that* it died,
15 minutes after the fact. The receiver's log tells you how long.

Each entry is stamped `[issun <version> / app <build>]` (`[relay <version> / app
<build>]` before 22 Sept 2026), the app build coming from `app_version` on every
push. **Don't split the log into per-version files.** Whether the phone survives
backgrounding is decided by the iOS build, not the receiver's, and the receiver
restarts far more often than the app changes —
splitting would fragment the data by the wrong variable and can't be undone.
A stamped line can be grouped any way you like later, which is what the
summary does. Entries predating the stamping group as "before builds were
recorded", so the pre-KeepAlive era stays visible as history without skewing
current numbers — no archiving needed.

## Where things stand

Working and verified: artwork via store ID, clickable title/artist/cover, album
line removed, versioning on both halves, both secrets (the key and the tunnel
token) rotated on 2 Sept 2026, and the progress
bar. The receiver autostarts as Issun, from the HKCU Run key.

**Verified — the watchdog fires, and survives the device powering off.** A
manual kill produced a notification 15 minutes later, corroborated by a
`00:16:02` gap. Better: on Sept 2 the phone's battery died at 20:17; the
notification was scheduled before that, fired at ~20:32 while the device was
off, and iOS delivered it on boot. The "pending notifications outlive the
process" premise is no longer theoretical.

**A gap is not proof that iOS killed the app.** Before concluding that,
account for the phone being off and for the app simply not having been
relaunched — nothing restarts Ammy after a reboot. The 01:25:34 gap on Sept 2
looked alarming and was a dead battery plus an hour before the owner reopened
the app. Many gaps since the `KeepAlive` fix have had a mundane explanation like
this one, so rule those out first, but not all of them: deaths continued after
it, about once a day as of 10 Sept, with a healthy engine and no explanation yet
(see "Still unexplained: what ends a run").

**Verified — the app survives the night.** Roughly eight unbroken hours on
Sept 2 with no gap logged, the first clean night on record. Compare the 39-hour
silent death of Aug 27–29 that prompted the `KeepAlive` interruption fix. One
night is not proof; check the summary in Issun's Diagnostics section
periodically and watch whether "never came back" ever appears.

Lifetime figures in the summary still include pre-fix history — the 39-hour
death dominates "longest" and "total silent time" and will for a long while.

**Rotating the key.** Issun makes a new one from its **New key** button, so the
value never appears in a chat or a screenshot. Then enter it in the app's
**Key** field; until then the receiver refuses the app's pushes.

**Done — `ammy://music` and `ammy://background` are gone (11 Sept 2026)**, along
with `BounceTarget`, `performBounce`, the private `suspend` selector,
`LSApplicationQueriesSchemes`, and the settings section that advertised them.
`CFBundleURLTypes` and `onOpenURL` returned on 14 Sept 2026 for `ammy://notify`
alone; see Open work item 2.

The scheme existed to tell Ammy what to do *after* launching. Nothing needed
telling: the app already starts reporting on launch, and the relaunch recipe had
already settled on `Open App [Ammy]` because the deep link made Ammy navigate
away itself and race the return. Its only remaining effect was to offer a worse
path beside the good one, in a section that read like instructions.

Two things went with it that were load-bearing elsewhere. `suspend` is no longer
called, so the App Review argument rests on the keepalive alone — still
decisive, see Distribution below. And `LSApplicationQueriesSchemes: music` is
gone; it was only ever there so the app could reopen Apple Music itself.

**Done — ingress moved to Tailscale Funnel (Sept 2026).** This removes the
single worst onboarding requirement: a stranger no longer needs a domain or a
Cloudflare account, only a free Tailscale login.

```
tailscale funnel --bg --https=443 localhost:8787
```

`--bg` is load-bearing — without it Funnel dies with the shell and does not
resume after a reboot. Public listeners are restricted to 443, 8443 and 10000;
the local target port is free, so 8787 stays as it was. The tailnet needs
MagicDNS, HTTPS certificates, and the `funnel` node attribute in the policy
file — the default policy grants that to every member, and the CLI links you
to whichever is missing.

**The URL is only as stable as the machine name.** `https://<machine>.<tailnet>
.ts.net`, and the machine half is auto-generated from the OS hostname unless
told otherwise — so renaming the PC silently moves the endpoint and the address
saved in the app stops resolving. Turn off "Auto-generate from OS hostname" in
the admin console. The tailnet half is fixed once certificates have been issued
for it. Cloudflare quick tunnels were rejected for exactly this failure mode,
except worse: a fresh hostname on every restart.

**Funnel is the only endpoint, since 25 Sept 2026 — by decision, not yet in
fact.** The Cloudflare tunnel that fronted the relay before Funnel is retired,
by the owner's choice to run the same setup everyone else gets (see the top of
this file). Don't put it in the app or offer it as a way to reach or test the
receiver. On 9 Oct 2026, and again on 27 Oct, it was still live in two places:
the `cloudflared` Windows service was running and its address still answered
with Issun's `X-Ammy-Relay` header, and Issun's **Public address** setting still
held it (imported from relay.py's `.env` on 22 Sept), which overrides the
Tailscale name for the window's endpoint and for cover URLs sent to Discord. By
4 Nov the address itself was gone: Google's and Cloudflare's resolvers answered
NXDOMAIN for `ammy.kaydenpmd.net`, so its DNS record has been deleted. The
service was still running, though, and Public address still held the dead
address, so the window's endpoint and any cover URL built from it pointed
nowhere. **Issun's half is done (13 Nov 2026):** the owner saw setup fill in
ammy.kaydenpmd.net and had the whole Public address override removed from
Issun (its build 127, "clear that publicbase mechanic"), and the value was
dropped from settings.json; Issun's address is Tailscale's, full stop.
Finishing the rest is the owner's: remove
the `cloudflared` service from an elevated shell, and, if the tunnel's public
hostname is still listed in the Cloudflare dashboard, delete it there. The token
lives in the service's registry `ImagePath` (token installs have no
`config.yml`), and refreshing it in the dashboard does *not* drop a connector
that is already connected; removing the service does.

**Done — playhead fixed (Sept 2 2026).** Cause was the arrival-time bug (Issun's
CLAUDE.md has it), not staleness in `currentPlaybackTime` as long assumed. After
the fix: zero `[playhead]` log lines, and 19 pushes across 15 tracks where a
single track used to generate thirty-odd — heartbeats now produce identical
payloads and get suppressed. The rule that prefers a reading implying the song
is further along has never fired; it is insurance, and no staleness has been
observed at all.

**Untested — the uploaded-JPEG path.** Neither relay.py's `art_cache\` nor
Issun's (`%LOCALAPPDATA%\Issun\art_cache\`, empty on 9 Oct 2026) has ever held
a cover, because every track played has had a store ID. It's a genuine fallback,
but it has never actually run.

**The September regression, and what it actually was.** From 4 Sept the app began
dying every 7–63 minutes during waking hours; before that, windows ran 8–87
hours. The break dates precisely to a phone reboot at 13:03–13:19 on 4 Sept, and
relay.py ran unrestarted across it, so the change was entirely phone-side. The
first instrumented build then showed `int=3/2` — a missed `.ended` — which the
old code could not have survived. It also showed `engine=yes` at every remaining
death, so that is not the whole story.

**Settled — the September regression, 10 Sept 2026.** The keepalive rewrite
worked, and the cause is confirmed with a number rather than a theory.

Measured on build 30, unaided (all Shortcuts relaunch automations deleted 9 Sept
11:28, so `appup` on a death line is the true lifetime):

```
17:29:49  phone stopped checking in  last seen 17:28:18
engine=yes want=yes  resumes=19 fails=3 heals=12  cfg=4 routechg=29  int=12/4
mem=27MB  avail=2071MB  availmin=2068MB  memwarn=26
lpm=no  thermal=nominal  appup=61445s
```

**17h04m in one continuous run**, overnight and through a full working day,
against a 7–63 minute baseline in the broken period. Prior instance on build 25
managed 12h37m.

**`int=12/4` is the whole story.** Twelve interruptions began, four ended —
**eight `.ended` events never arrived**. Under the pre-September code, recovery
depended solely on `.ended`, so the *first* of those eight would have stopped the
audio engine permanently and the app would have been reclaimed within the hour.
`heals=12` is the self-heal catching each one; `fails=3` is resume failures that
retried and recovered. Do not remove the retry loop, the 10-second
`engine.isRunning` check, or `keepAlive.verify()` on every push, which still
checks the engine when iOS throttles the timer in the background — this line is
what they are for.

**Three suspects eliminated, and worth not re-testing:**

- *Memory / jetsam.* `availmin=2068MB` across seventeen hours, while `memwarn=26`
  says the system was under pressure repeatedly and told the app about it. The
  app's own headroom was never threatened. A 27MB footprint dying is not a
  memory story.
- *Low Power Mode.* A death on 9 Sept occurred with `lpm=no` after an earlier one
  with `lpm=yes` had made it look causal. It is not.
- *Thermal.* Deaths have occurred at `nominal`, the coolest state.

**Still unexplained: what ends a run** — partly explained since 14 Nov 2026 by
the phone's journal: most deaths it has seen follow an interruption that froze
the app before it could restart (see "What the journal showed", below). Every
death recorded since the fix but two (below) has carried `engine=yes want=yes` — a healthy audio engine — with no
correlate in any signal collected. It is now a roughly once-a-day event rather
than an hourly one: build 158 (3 to 11 Nov 2026) died nine times in about eight
and a half days, after runs of 2 to 24 hours. Whether that is worth chasing
further is a judgement call, not an open bug.

**The census of 11 Nov 2026**, every log from 24 Aug (relay.py's and Issun's,
read with PowerShell; the scripts, tables and log copies are in
`local/keepalive-2026-11-11/`, never committed because the logs carry listening
history, with a `NOTES.md` saying what each file is). Of 66 death verdicts since 11 Sept, 3 are unsound (same process
through the gap), 17 are installs of a new build, 17 are phone reboots inside
the gap, with Low Power Mode on at the last push in 15 of them (a battery
running out, most likely), and 29 are unexplained, 27 of them with the engine
running. Low Power Mode was on at the last push in 45% of the unexplained deaths
under Issun, against 27% of the time alive and 8% of silences survived. 19 of
132 silences began within two minutes of the top of an hour, against 4.4
expected, 7 at 10:00 and 5 at 13:00, which looks like a scheduled interruption
such as an alarm. And 24 gaps Issun labels "the path failed, not the app" had no
failed pushes at all: the app wasn't trying, so those were suspensions, 19 of
them ended in the background by an interruption's `.ended`. From Issun's build
48 those read `— suspended, no pushes failed`, and a gap that began with Stop's
goodbye reads `— stopped on the phone`, as does the silence line before it.

**The two exceptions: the keepalive failed to restart.** Since build 25, 15
engine stops were seen at a push. 12 came with a failed restart, every one while
an interruption was under way, and 10 of those were playing again by the next
push, 3 to 33 s later, through an `.ended` or a self-heal. The other two never
pushed again and were dead when the phone next checked in: 17 Sept 2026 at
10:00:02 (build 51, `setActive: Session activation failed`, int 3/1) and 4 Nov
2026 at 18:50:06 (build 158). On 4 Nov interruptions had piled up (eight began,
one ended); the engine stopped, `setActive` succeeded, and `engine.start` failed
with `com.apple.coreaudio.avfaudio error 2003329396`, whose code spells 'what',
AVAudioSession's unspecified error. Ammy stayed silent until it was opened at
22:20. The 10-second retry never got its chance, most likely because iOS
suspends a backgrounded app soon after its audio stops, and it is the case the
retry loop can't cover. Since build 167 a refused `engine.start` makes the next
try build a fresh engine, the usual cure reported for 'what', and the journal
(Diagnostics) records what follows.

**The keepalive hold, parked (11 Nov 2026).** The obvious fix for those two was
to hold a `UIApplication` background task from the first sign the engine is down
and retry at 1, 2, 3, then every 5 s within iOS's ~30 s grace. It was built and
tested in the `keepalive-lab` lab (never merged; the code at 2fd0e28, its
results in `lab/results/` since 1301c27; the Apple pages, SDK headers and other
apps' code read for it are in `local/keepalive-2026-11-11/`), on the iOS 26.5
SDK build on iOS 27.0 and on 26.5. The ladder and its bookkeeping worked: with
`engine.start` refusing ('what') for 15 s, it played again at +16.6 s. But the
lab found two ways it gets Ammy killed outright, which is worse than a
suspension, since a suspended Ammy can still be woken by an `.ended`:
- after iOS's deadline, the next `verify()` opened a new hold with no time left,
  its expiry handler never ran, and RunningBoard terminated the process
  (`0x2182BAD2`, "Timed-out waiting for process ... to invalidate assertion ...
  Shared Background Assertion"), 0.6 to 4 s after the reopen, on both iOS
  versions;
- on iOS 27.0, a real audio call held the main thread for about 12 s, past the
  deadline, so the expiry handler couldn't run either (seen only in the
  simulator, whose audio HAL is in-process).
And the simulator can't show whether a hold saves anything: RunningBoard never
suspends an app with the audio background mode there ("Ignoring suspend because
this process is simulated and has background audio capabilities"), and its audio
HAL takes playback assertions on the first resume and never lets them go. The
owner chose "Ship the safe half": the journal, the failure codes and the fresh
engine, without the hold. Revisit it only with the journal's evidence from the
phone of what follows an engine stop, and then with two guards at least: never
begin a task in the background with under ~10 s of `backgroundTimeRemaining`,
and release it a few seconds before the deadline rather than relying on the
expiry handler alone.

**What the journal showed, 14 Nov 2026 (build 177, 12–14 Nov).** Six deaths.
Two were phone reboots with Low Power Mode on (12 Nov after 14:01, 13 Nov after
03:12; the next launch's `devup` was hours, not days). The other four were the
same thing: an interruption (reason 0 every time) stopped the silence and the
process stopped running within seconds, before anything retried. 14 Nov at
01:19 and 01:47 the journal ends `interruption began` and the last tick is 2–3
s before it; 13 Nov 23:58 the audio came back and a second `.began` a second
later was the end; 13 Nov 07:04 ends `verify: engine stopped` with no outcome,
and the tick that ran that verify left no stamp. Three of the four gaps last
15 minutes (15:14, 15:09, 15:59): the silence warning fired and the owner
opened Ammy, which came up as a new process, so iOS had removed it while it
was suspended (or it was swiped away; the log can't tell). Two other
interruptions, 12 Nov 10:00 and 22:11, did the same and were still in memory
at the 15-minute reopen: those are the `suspended, no pushes failed` gaps.
The pattern is a race: in the same journals, a `verify()` that happened to run
0–5 s after `.began` played again 12 times out of 14 (the two refusals were
'!int', and played at `.ended` a second later). Until then `.began` did
nothing. **Since build 181** it tries at once and at +1 and +3 s
(`KeepAlive.restartAfterBegan`, no background task), the journal writes
`activating session` and `starting engine` before those calls in the first
tries of a recovery, and the tick stamps before its check. Released 14 Nov
2026 at the owner's "Yes, release it" (GitHub Release v1.0-b181, in the
source the same morning). Not yet seen on a device, nor installed as of that
release. **Next: read Issun's log after a day or two on 181.** Per
interruption the journal should now read `interruption began`, `after began
+0s: engine stopped, trying`, `activating session`, `starting engine`,
`playing again ...`, then `after began +1s/+3s: still playing`. A death's
`[keepalive] journal:` lines say how far that got. Also unanswered: what the
owner was doing on the phone at 23:58, 01:19 and 01:47 on 13–14 Nov, which
would name the interrupter. If the next deaths end between `.began` and a restart's outcome, that
is the evidence for a short hold with the lab's fixes (at most ~5 s, opened
only at `.began`, ended from a utility queue, never reopened until the silence
has played or the app has been in front).

## Scanning a receiver's QR code

Since 12 Nov 2026, a **Scan QR Code** row under URL and Key opens VisionKit's
scanner (`CodeScanner.swift`). A code holding `{"endpoint": "...", "key": "..."}`
fills in both fields and closes the sheet. Either value may be missing (Issun's
owner, 12 Nov 2026, since Issun's setup can leave one out): the code then
fills in only the field it carries and leaves the other as it was. A code with
neither, or with an endpoint that isn't https, is ignored and logged, as is
any other code. Issun's setup window shows one (`PairingCode` there); the payload is
plain JSON, not a link, so neither app names the other. The row is hidden
where VisionKit can't scan. Camera access brings `NSCameraUsageDescription`,
which is also in `source.config.json`'s `appPermissions`, since SideStore and
AltStore compare the two. Every word of it is the owner's (`[sample]` on the
wording page, claude.ai/artifact/BKtxXmKxc3ot9CSi7D2xRJ). Built on CI on its
branch; not yet seen on a device, and not yet scanned against Issun's code.

## Open work

**1. Shippable to others**, in the order things actually block:

- ~~The relay is a dead end on first run — it exits with "Set RELAY_KEY", which
  a new user cannot act on. It should generate its own key, write its own
  `.env`, and show it (a QR the app scans would remove the typing entirely).~~
  **Discarded 18 Sept 2026: Issun's job, not relay.py's.** Fixing `relay.py`'s
  first-run experience would be throwaway work — key generation belongs in
  whatever the user actually runs, and that's meant to be Issun, not a raw
  Python script started by a Scheduled Task. See the self-provisioning-
  executable bullet below, which is a description of Issun.
- **Autostart is Windows-only.**
- ~~**Each user needs their own Discord application**, which is a five-step
  detour of its own.~~ **Done 14 Nov 2026:** Issun builds in one application
  ID, and the "Listening to" text comes from the source's `activity_name`
  (see "The receiver on the PC").
- Counted end to end, a stranger needs three accounts — Discord, Tailscale,
  Apple — and about eight steps. The biggest lever was packaging the receiver as
  one self-provisioning executable that generates its own key and registers its
  own autostart. That executable is **Issun**, not a second thing to build.

**2. Shortcuts relaunch automations.** Built 9 Sept, then deleted to get a clean
stability measurement. Worth rebuilding only if the app still dies. The recipe,
so it is not re-derived:

- One shortcut holds the logic and the secret: `GET /status` with an
  `X-Relay-Key` header → `If` contents **contains** `stale` → `If Is Locked`
  (do nothing; an app cannot be launched from the lock screen) → `Otherwise`
  `Open App [Ammy]` then `Open App [Current App]`.
- `Get Current App` must run **first**, before anything else — once Ammy is
  foregrounded, "current app" is Ammy.
- Use `Open App` to launch. The old `ammy://` scheme was removed on 11 Sept
  2026 because it made Ammy navigate away itself and race the return; that
  behaviour now lives in the shortcut, and it stays there.
- `Open App` restarts a session that failed (build 91 and later): coming to the
  front restarts any session that didn't end by the person pressing Stop. Before
  that, autostart ran only on a cold launch, and a session that failed — for
  example after the PC slept past the 20-minute retry window — left the process
  suspended rather than dead, so opening it did nothing and `/status` stayed
  `stale`.
- A scheme was reinstated on 14 Sept 2026 for an unrelated job, and the two
  should not be confused. `ammy://notify` opens the app exactly as `Open App`
  does and changes one thing: a connection failure arrives as a notification
  rather than a popup. Use it from any shortcut that switches away from Ammy
  immediately, because being frontmost at the instant of failure is not the
  same as being looked at, and no amount of inferring from scene phase can tell
  those apart — the launch has to say so. One-shot; it describes the connection
  attempt it was opened for and nothing after.
- Triggers are per-device and **cannot be shared** — Apple: "Personal automation
  is specific to a device." Only the shortcut can be handed over, as an iCloud
  link. A tutorial has to list the triggers for people to recreate.
- Good triggers are transitions: Music opened, Bluetooth connects, CarPlay.
  Wi-Fi join/leave mostly fires while the phone is locked, when nothing can
  launch anyway.

**3. `Is Running` is unverified.** The Shortcuts App type exposes `Is Running`,
which would let the phone answer "is Ammy alive?" locally — no network call, no
secret in the shortcut, and the single worst onboarding trap gone. Apple
documents none of these properties. The property set mirrors macOS's
`NSRunningApplication`, which is encouraging but not evidence. **Test it against
a real death, not a force-quit** — force-quitting removes the app-switcher card,
so it cannot reproduce the case that matters. If `Is Running` is switcher-based
it will report `true` for an iOS-killed app: wrong in exactly the situation it
is needed, and silently.

**4. Distribution — decided 10 Sept 2026, don't re-open without new facts.**
The IPA stays as it is: published unsigned from CI, and people install it however
they like — SideStore, AltStore, a jailbreak, whatever they already have. That is
a deliberate choice, not a fallback.

**The floor is iOS 26, raised from 17.0 on 11 Sept 2026.** The Start button sits
in a `safeAreaBar`, which is iOS 26-only and is what supplies the scroll edge
effect behind it; there is no pre-26 equivalent, and a hand-rolled fallback would
be a second code path visible only on devices the owner does not have and cannot
test. Anyone on 18 or earlier can no longer install the IPA at all. That is a real
cost and it was accepted knowingly — it is recorded here rather than left to be
discovered from a build error, and the reason is repeated beside
`deploymentTarget` in `project.yml` so it does not get quietly reverted.

What was considered and why it lost:

- **App Store: structurally impossible.** The silent-audio keepalive is a
  straight rejection on its own, and no legitimate background mode delivers
  30-second updates — `audio` demands real audio, `fetch` and `processing` are
  opportunistic and measured in hours. There is no version of this app, as
  designed, that passes review. The private `suspend` selector was a second
  rejection until it was removed with the URL scheme; the conclusion never
  needed two legs.
- **AltStore PAL: wrong audience, and Apple stays in the loop.** A developer can
  distribute from anywhere, but users must be in the EU, Japan or Brazil, which
  excludes the owner and most people near them. It also requires notarization of
  every build (nobody has established whether a silent-audio keepalive survives
  it), a paid account, the Alternative Terms Addendum, and self-hosting the
  distribution package. Worth revisiting only as a bonus channel for those
  regions, once the app is stable and the setup documented.
- **Ad-hoc distribution** off a paid account is real and works — 100 device UDIDs
  a year, one-year validity, recipients need no sideloader at all. Front-loads the
  friction onto the owner instead of every user. Available if a small circle ever
  wants it, with the caveat that it means signing a review-violating app under
  your own developer identity.

The observation worth keeping: the unofficial route grants *more* freedom than
the sanctioned one. SideStore uses developer provisioning — the mechanism Apple
leaves open for testing your own apps — and that path carries no notarization, no
terms addendum and no geofence. The price is paid in expiry dates rather than in
permission.

The only thing that would dissolve the problem instead of managing it is a
**different sender**: Apple Music's API can report recently-played tracks with no
iOS app at all, so nothing to sideload, nothing to keep alive, nothing to die.
The cost is real — no playback position, so no progress bar, and updates lag
rather than being live. It fits the modular shape though: same receiver, two
senders, one live and one effortless.

**5. tvOS** was investigated. `MPMusicPlayerController`, `systemMusicPlayer` and
`nowPlayingItem` are all available on tvOS 14+, so the reading side ports.
Unknown: whether the silent-audio keepalive survives tvOS backgrounding. Cheap
to test with a stub target before committing to it.

**6. Pushes can reach the receiver out of order — done, 18 Sept 2026.** Each push
is an independent `Task` with no ordering guarantee against the others, so the
farewell `stop()` sends (`playing: false`) could land *before* a push that was
already in flight saying `playing: true` — leaving Discord showing a track
after Ammy stopped broadcasting it. Found 12 Sept 2026 while fixing the same
staleness on the app's own side, where a session counter now makes an orphaned
push keep quiet (`PresenceController.session`). That counter couldn't help
here: the receiver has no way to know which session a request belonged to.

`PresenceRelay.push()` now stamps every push with `seq` — milliseconds since
epoch, not an incrementing counter, because a counter resets to 0 on relaunch
and the receiver would then reject every push from the new process as "older"
than whatever high number the last one reached. The receiver drops a push whose
`seq` isn't newer than the last one it accepted, and logs it rather than
failing silently — relay.py from 1.9.0, and Issun's `PhoneState`, which also
lets a relaunched app's push supersede the old `seq` (item 7). A build that
doesn't send `seq` is unaffected; such a push is always applied, the same
compatibility rule as the old key header.

**7. Ammy's half-open sessions — handled in Issun.** A failed push tears Ammy's
session down *without* the farewell, because there is nothing reachable to send
one to, so a receiver routinely holds a session whose phone has already moved
on, and then that same phone starts a fresh one. Any receiver has to key and
supersede sessions, or expire them on silence, never stack them. Issun does: a
push whose `app_uptime_s` fell further than its `seq` did, by more than a
5-second slack, comes from a new app process and wins. Uptime merely going
backwards isn't enough, because a request overtaken in flight comes from the
same process (`PhoneState.cs`; Issun's CLAUDE.md).

**8. Errors: named, recorded and announced — done.** Every terminal failure
becomes a `FailureNotice` and goes through `fail()`, which sets the status row
to Disconnected, records the failure in `EventLog`, and calls `announce(_:)` in
`PresenceController`. `announce` shows a popup (`pendingFailure`, the alert in
`AmmyApp.swift`, titled `PushOutcome.failureTitle`, "Connection Failed", which
the notification shares) when `UIApplication.shared.applicationState ==
.active`, and a notification via the watchdog otherwise. Deferring the popup to
the next foreground was rejected because push failures overwhelmingly happen
while Ammy is backgrounded. `appDidEnterBackground()` turns a popup shown to an
empty room (Ammy launched by a Shortcut, failing while technically frontmost,
switched away a frame later) into a notification, and `suppressNextPopup()`,
driven by `ammy://notify`, skips the popup for a Shortcut that is about to
background Ammy on purpose.

The history is `EventLog`/`LinkEvent`/`LinkHistoryView`: all three things that
can happen to a link — `.failed`, `.interrupted`, `.recovered` — behind an
All/Failures filter, newest first, persisted to UserDefaults and capped at 100,
reached from the `History` row at the foot of the page. Because recording
happens inside `fail()`, no failure can end a session without being recorded.

*The precondition.* `PresenceRelay.push()` returns `PushOutcome` rather than a
`Bool`. `PushOutcome.summary` is the short label History lists, and
`explanation` is what the popup and the notification show (see the note after
this item's inventory). A dead receiver reads "Connection Refused" (or
"Connection Cut Off" behind a broken Funnel), a wrong key "Key Rejected", the
receiver's own 404 "Wrong Path", and Funnel's 404 "Nothing at That Address".

Receiver side: Issun stamps `X-Ammy-Relay: <version>` on every response, errors
included (relay.py did on most). It exists because status codes alone cannot
separate the receiver's own 404 (wrong path) from Tailscale Funnel's 404
(hostname resolves, nothing served on that port). Presence of the header is
what `PushOutcome.refused(fromRelay:)` carries.

*The inventory, so it is not re-derived.* Handled before any request: `http://`
typed, an address that will not parse into an https URL with a host, and denied
media access (the access prompt at the top of the screen, which replaced the
Media Access row on 24 Sept 2026). What `PushOutcome` now names:

- Transport (`URLError`, swallowed by `try?`): `.notConnectedToInternet`
  (which is also what cellular data switched off for Ammy alone produces, per
  Apple DTS), `.dataNotAllowed` (roaming, or cellular off for the whole device),
  `.cannotFindHost` and
  `.dnsLookupFailed` (the Tailscale name does not resolve), `.cannotConnectToHost`
  (resolves but refuses — receiver not running, or port closed), `.timedOut`
  (bounded by the 10s request / 20s resource caps), `.networkConnectionLost`
  (dropped mid-request; the wi-fi to LTE handover), `.secureConnectionFailed`
  and the certificate errors, `.cancelled`.
- HTTP from the receiver's `POST /now-playing`: **401** key missing or wrong;
  **404** path is not `/now-playing`, which is what pointing at the host root
  gives you; **400** body was not valid JSON. Success is 204.
- HTTP from Tailscale Funnel, in between and not the receiver at all: 502/503 when
  the funnel is up but the node is not, and Funnel's own 404 when the hostname
  resolves but nothing is served on that port. *Unverified, and contradicted
  once:* on 24 Sept 2026, with the node unreachable through Funnel, Funnel's
  edge sent no HTTP status at all. It dropped the TLS handshake, which iOS
  reports as `secureConnectionFailed`. The code treats 502 as "PC up, nothing
  listening".

ATS is *not* reachable: `http://` is rejected before any request and
`normalised()` requires an https scheme, so `.appTransportSecurityRequires-
SecureConnection` cannot fire.

*Settled 14 Sept 2026 — and it dissolved the decay question rather than
answering it.* Reasons do not go on the status row at all. The row reports
state — Disconnected, Connecting, Connected, Reconnecting — and nothing else.
A reason describes one moment in the past while the row describes now, so
parking one there left the screen asserting something that had stopped being
true the instant it appeared. Reasons go to the alert, the notification and the
history, all of which are either dismissible or timestamped. Nothing is left to
decay: after a failure the row reads Disconnected, which is simply true.

`teardown(reason:)` now carries an optional reason in place of a separate
notify flag — a reason being present at all is what distinguishes a failure
from a deliberate stop.

*24 Sept 2026: a label is not an explanation.* After a PC restart left Tailscale
Funnel broken, all the owner saw was "Secure Connection Failed" — "i don't
think ammy is very good at communicating errors still." The label was accurate
and useless: it reads like a certificate fault, and here it meant the PC
couldn't be reached. So a failure is now a `FailureNotice`: `summary`, the
short label History lists, and `explanation`, the likely cause and what to
check, which the popup and the notification show. Each adds its own way to
retry: "Press Start to try again." in the popup, where the session is over and
the app is already on screen, and "Open Ammy to try again." in the
notification, because coming to the front restarts it. The popup's title stays
"Connection Failed", and where each notice appears is unchanged. When adding a
failure case, write both halves, and keep the explanation about "the receiver"
and "the address", never a product.

**Why `secureConnectionFailed` means "unreachable" here.** Measured 24 Sept
2026 with check-host.net from Los Angeles, Dallas, Atlanta, Miami and New York:
with Funnel's route to the PC broken, Funnel's public edge accepts the TCP
connection and drops it mid-handshake ("Broken pipe"), and iOS reports that as
`secureConnectionFailed`. That day matched Tailscale bug
[#21114](https://github.com/tailscale/tailscale/issues/21114) on 1.102.3 on
every symptom: after a control-plane reconnect, Funnel stops serving public
traffic while `tailscale funnel status` still says "Funnel on" and the PC
reaches its own address fine. A symptom match, not a proven cause. Restarting
the Tailscale service didn't clear it. Updating to 1.102.4, which rebooted the
PC, did. **Don't test Funnel from the PC itself.** Its lookups of its own
ts.net name are answered by Tailscale with the tailnet address, even when
another DNS server is named, and a request forced through Funnel's public
addresses from the PC is not a trustworthy stand-in either. Test from outside.
check-host.net is the instrument that agreed with the phone. Claude's own web
fetcher got through three times that night while the phone, Safari and all
five check-host cities could not, so don't rely on it alone. For the public
DNS records, use DNS-over-HTTPS.

**25 Oct 2026: the address vanished from DNS, and a toggle fixed it.** Ammy
stopped connecting; Issun's last push from the phone was 22 Oct 00:08. Issun
was running and answered `ok` on 127.0.0.1:8787, and `tailscale funnel status`
said "Funnel on". The node was online, its key valid until March 2027, the
`funnel` attribute present, no health warnings, already on 1.102.4. But this
time public DNS had no record at all: DNS-over-HTTPS (Google and Cloudflare)
answered NXDOMAIN for the ts.net name, and check-host.net failed from five
cities with "No such device or address". Claude's web fetcher got `ok`
through anyway, again. Turning Funnel off and back on with the same setting
republished the record within seconds, no reboot:

```
tailscale funnel --https=443 off
tailscale funnel --bg --https=443 localhost:8787
```

For the first minute some check-host cities got "Broken pipe" (the 24 Sept
symptom) while others got 200; a minute later every city that could resolve
the name got 200. Resolvers that had cached the NXDOMAIN kept failing for up
to five minutes, the zone's negative-cache TTL, and the phone can too:
Airplane Mode on and off clears it.

So when Ammy can't connect and Issun answers locally, look it up with
DNS-over-HTTPS first. NXDOMAIN means toggle Funnel. If the name resolves and
check-host still gets "Broken pipe" after a minute or two, it's the 24 Sept
failure, and what fixed that was a reboot.

**9. The bottom bar's distance from the screen edge is unconfirmed by touch.** A
home-button phone has a bottom safe area of zero and a Face ID phone 34pt, so a
constant pad is wrong on one of them. `AmmyApp.swift` reads `bottomSafeArea`
from an `onGeometryChange` on the `NavigationStack`, attached after the stack's
own bar. That puts it outside the bar, because reading the safe area inside a
`safeAreaBar` is circular; it is
`onGeometryChange` rather than a key-window read because iPad rotates and
resizes, and rather than a `GeometryReader` because that would take over the
layout beneath it. The bar pads `.padding(.bottom, edgeGap - bottomSafeArea)`
with `edgeGap = 21`, which pins the button 21pt above the true screen edge on
every device. "No clamp needed" was said of that formula and was wrong: the
reading counted the keyboard, and from build 77 to 172 the bar went behind it
(Gotchas, "The bar went behind the keyboard"). Since then `bottomSafeArea` is
read with the keyboard ignored, and with the keyboard up the bar sits `edgeGap`
above it. System bars don't stop at the top of the
home-indicator zone; they intrude about 13pt into it. Pixel-measured on an
iPhone 16 Pro Max screenshot (18 Sept 2026), Shortcuts' floating tab bar sat
21.3pt above the edge; on the SE, Music's tab bar ends 19pt from it. The read
itself is settled: on 18 Sept 2026 `bottomSafeArea` read 34 on a real Face ID
phone, so if the bar still sits wrong, question `edgeGap`, not the read. **The
result is not yet touched on a real device.** This is a screenshot measurement, and the project's
rule for this class of question (see Gotchas, glass button styles) is to build
it and touch it. Check both a Face ID phone and the SE. Almost no subscriber is
on a home-button phone, so this is the default first impression, and the iPad
screenshots for `source.config.json` wait on it, or the listing ships pictures
of the wrong bar.

**Note the shape of the mistake**, because it is the exact inverse of the
`safeAreaBar` win recorded in Gotchas. The tint tracked an OS change for free
because nothing was drawn by hand; this failed to track a *device class* because
a constant was.

**10. Long titles ease into a stop, as Music's do — built 1 Nov 2026 (builds
145 and 148).** Asked 15 Oct 2026: "can you make
the long-title scrolling ease into a stop like what happens in apple music if
that's easy to match exactly". `MarqueeLine`'s first numbers were
LNPopupController's (cbpowell's MarqueeLabel, linear). The owner then
suggested UIKit's private marquee ("how about just lnsystemmarqueelabel"); it
shipped in build 120, and the owner reported "there is no easing visible in
build 120", the same day.

The recording arrived on 1 Nov 2026, after the chat's 30 MB attachment limit
turned it back. It was already on the PC: the owner's iCloud Photos syncs
through iCloud for Windows, and it is
`Pictures\iCloud Photos\Photos\ScreenRecording_11-01-2026 04-29-11_1.mp4`.
1:40 of Music's full-screen player on the owner's SE (iOS 27.2), 750x1334
HEVC at a variable ~59.5 fps, 5958 decoded frames. Music only, so it says
nothing about which scroller build 120 ran, which no longer matters.

**How, so it can be redone: `scripts/measure_marquee.py`.** Give it a
recording, the line's pixel rows and a stretch of columns clear of both
fades (`... rec.mp4 784 840 --columns 150:450` for this one). It finds the
line in every frame at that frame's own pts_time, on a 0.01 px grid, against
an earlier frame rather than the one before: build 145's version added up
frame-to-frame moves, whose small errors lean one way with the fraction of a
pixel moved, and read each scroll here 0.4–0.6 pt long. For every scroll
from rest to rest it prints the distance, the peak speed and the cubic
Bézier that scroll fits on its own; then every frame of the title against
the model below, with the hold and speed that fit it best; then the loop
periods, and how soon after a song change the line first moved. It takes
about a minute here. A rest is half a second without movement, timed to when
the line set off, so a recording that sends frames far apart while nothing
moves, or none at all, still has its rests, and a lone still frame before a
gap mid-scroll isn't taken for one. Loops and first moves
are timed from when the line set off: its first moving frame, taken back at
its own speed. After a gap in the recording it looks for the line as far as
it could have gone, but once the line is moving, no further than twice as
far as its speed would carry it, plus 12 px, so a new title that begins
like the old one isn't taken for the old one moving on, unless it sits
within that reach, as in the 0.87 s case below.

It was tried on 22 synthetic recordings of the model (26 runs, some repeated
with other rows or columns): Ammy's row and Music's player, at 2x and 3x,
light and dark, with dropped frames, gaps of up to 2 s, frames far apart or
none while the line rests, odd crops, loops over 1,000 pt and song changes.
In all but two it gave back 3.00 s and 30.0 pt/s (2.99 s in three), the
distances to 0.07 pt, and the loops and first moves to 3 ms, or to 0.11 s
where gaps of up to 2 s covered a scroll's start. A song change inside a
gap is timed at the first frame after it, so the first move after one reads
short by up to the gap, or, if the gap left under half a second of the new
title's rest in view, isn't timed, since the next rest is a loop later. The
two it gets wrong: a title that changed during
a rest to the same words plus (Live), which looks no different until the
line moves and which it takes for the same title, so it fitted holds of
3.91 and 3.54 s at 28.4 and 27.8 pt/s and a 14.29 s loop spanning both
titles; and a change, inside a 0.87 s gap, to the same title again, which
sits just where the old title's last speed would have carried it, though,
slowing to its stop, the old title wouldn't have got there yet. Eight more,
made in review for the newest code, come out right: a recording that starts
mid-scroll with its second frame 0.6 s late, a repeated frame before a
0.6 s gap, a song change during a rest with no frames, and gaps that leave
a new title under half a second of rest in view. Numbers
below that it doesn't print either name their source or came from one-off
measurements and calculations on 1 Nov 2026 that aren't in the repo. Those
include the Baditude figures, the gap's clear space, the fades, the title's
resting place and the cap height.

What Music does, from two titles that looped in full: 'Light the Fire Up in
the Night "KAGEJIKAN"', 426.5 pt a loop, and 'Shoot to kill, kill your
darlings', 299.0 pt (the script prints 426.49 and 298.96; the independent
measurement found 426.50 and 299.00):
- **A plain marquee, eased as a whole.** It holds 3 s, then scrolls at
  30 pt/s until the repeat has taken the text's place, and that whole loop,
  hold and scroll together, runs through ease-in-ease-out, Core Animation's
  (0.42, 0, 0.58, 1). The ease-in stretches the hold into a rest of over
  4 s, longer for a longer title (4.98 and 4.32 s here); the scroll sets off
  already moving, is fastest at the loop's midpoint (51.8–51.9 pt/s on both
  titles, where the model's is 30 pt/s times the curve's peak slope of 1.72,
  51.7), and eases to a stop as the loop ends. Against every frame of both
  titles, rests included, with nothing fitted but where each title's loops
  start, it misses by 0.42 and 0.21 pt RMS, and by under 1 pt on every frame
  but one. The misses near 1 pt are KAGEJIKAN's first loop, which ran 24 ms
  longer than 3 s plus its distance at 30 pt/s (next bullet); given that
  loop its own start, it misses there by under 0.1 pt on every frame but the
  same one. That frame, at 2.495 s, misses by 1.7 pt, 0.9 from the loop and
  0.8 from its own timing: its timestamp is out of step with its neighbours'
  (28.3 then 21.7 ms apart, the only such steps in the recording), and it
  shows the line where its neighbours put it 16 ms after that timestamp.
  Left free, the hold and speed come out at 3.01–3.02 s and 30.0 pt/s, and
  at 2.997 s and 30.001 pt/s in the independent measurement.
- **The evidence that it is one eased loop**, not an eased scroll after a
  rest: the loops repeat 0–25 ms after 3 s plus the distance at 30 pt/s
  (17.217 and 12.967 s). The script times them at 17.219 and 12.982 s, and
  fits of each loop on its own (the review's, 1 Nov 2026) put KAGEJIKAN's
  first at 17.241 s. The extra is a pause at rest before the next loop,
  which fits Music building each loop when the last one ends (below);
  Ammy's loop runs off the clock and has none. In those fits the peak speed
  falls at the middle of each loop (19.49 s against 19.49 s, 87.75 s
  against 87.75 s), and the rests are what the curve leaves of the hold
  (4.98 and 4.32 s) plus that pause; the script's "still for 5.21 and
  4.51 s" also counts the slow end of each scroll, under 0.05 px a frame.
  Fitted alone, each scroll is a different slice of the same curve, which is
  why their best Béziers differ, (0.330, 0.345, 0.567, 0.994) and (0.319,
  0.380, 0.568, 0.988), each within 0.012 of its slice of the eased loop,
  (0.329, 0.347, 0.566, 1) and (0.318, 0.384, 0.567, 1). Keep three places:
  rounded to two they fit several times worse. They aren't exact, though:
  the fit has a long valley of near-best answers, and started from when the
  line set off rather than from its last still frame, Shoot to kill's comes
  out (0.317, 0.387, 0.564, 1.010) at 0.022 pt rms against 0.021, so the
  script tries both and keeps the better. The named curves applied to
  the scroll alone miss by 2.6–18 pt; ease-out is the nearest. It was the
  independent re-measurement, a second agent working from the same recording
  without seeing these numbers, that found the whole-loop structure.
- **Corrected the same day.** Build 145's version of this item took its
  distances and per-scroll Béziers from the drifting frame-to-frame track
  (426.9 and 299.6 pt), and its periods and rests from a superseded first
  model (an averaged Bézier after a fixed rest), and said the script
  reproduced them all, which it didn't. A review by independent agents
  found each one on 1 Nov 2026; these are the corrected numbers. Two more
  reviews, of build 148 before it shipped, found more of the same: this item
  gave the build as 146, a number no build will carry, overstated the
  synthetic tests, explained only half of the 1.7 pt miss, claimed every
  number the script doesn't print named its source and missed the second
  recording; and the script lost a song change hidden in a gap, timed
  starts from the last still frame, counted a rest in frames rather than
  time and, when a gap hid most of a new title's first rest, timed its
  first move a loop late. All are fixed above, though a song change in a
  long enough gap can still be lost (the 0.87 s case).
- After a song change the first scroll came 4.28 s and 4.65 s after the new
  title appeared: one rest of the loop that ran, which began 37 and 38 ms
  before the title showed (the curve leaves rests of 4.318 and 4.684 s for
  those loops). A loop starts with its hold. The second,
  'Baditude (Original Radio Edit)', ran a 15.24 s loop, not the 13.07 s its
  own 302 pt needs. 15.24 s is what the previous song's artist line needed
  ('digifae, diana starshine & Galen Tipton', about 367 pt with the gap), so
  Music sized the shared loop (below) while that line still held the
  previous song; Baditude's own artist line didn't scroll. It is the first
  recording's only sight of the shared loop, and the next bullet has a
  direct one. Ammy's row sizes the loop from both lines as they are after
  the change, so it doesn't copy that.
- **A second recording shows the shared loop directly.**
  `ScreenRecording_11-01-2026 17-30-58_1.mp4`, in the same folder, is 50 s
  of the same player on the same phone at 17:30 that day, and its title and
  artist line both scroll: 'Prime Time Golden Hour Show (Soundtrack)',
  437.0 pt a loop, and 'Shiori Sasaki, ATLUS Sound Team & ATLUS GAME MUSIC',
  535.5 pt. Run on rows 784 840 and 836 892, columns 150:450 for both, the
  script has them setting off within 2 ms of each other and both repeating
  every 20.85 s (it times them at 20.852 and 20.854 s): the artist's own
  loop, 3 s plus 535.5 pt at 30 pt/s, which it fits at 0.16 pt rms (left
  free, 3.01 s and 30.0 pt/s). The title's own 437.0 pt would need 17.57 s,
  and on that loop the model misses it by 60 pt rms. Instead it keeps the
  artist's pace, peaking at 51.8 pt/s, and after 9.6 s stops where it runs
  out, then rests 11.2 s. From the positions file the script writes: the
  title stops from about 35 pt/s, with no easing, and the artist's loop
  with the title held at its own 437.0 pt puts it within 0.07 pt rms of
  every frame, 0.7 pt at most.
- **The gap is 32 pt.** There is 35.7 pt (KAGEJIKAN) and 34.0 pt (Shoot to
  kill) of clear space between the end of the title and its repeat, to the
  ink's half-coverage edge, and SF Pro Semibold's side bearings at 20 pt
  (3.58 and 1.84 pt) make both a 32.1–32.2 pt gap between the two copies.
  The font file is on this PC, in
  `%LOCALAPPDATA%\Microsoft\Windows\Fonts\SF-Pro.ttf`. Apple's code sets 32
  (below).
- **The fades are 20 pt.** Both are straight ramps 18.5–20.3 pt wide (10% to
  90%, over 0.8): the leading one from about 8 to 28 pt across the screen,
  short of the title's resting place at 32 pt, so a title at rest or easing
  into place is never faded at its start; the trailing one ending at about
  258 pt, inside the title's column. Apple's 26.1 code was read as setting 24
  (below). A video whose brightness isn't in proportion to opacity can't
  explain that, since it would bend the ramp rather than straighten it at
  20 pt, so the row follows the phone. The row has no margin beside its
  artwork, so both of its fades sit inside the line, and the leading one
  fades only the copy that's leaving: it ramps in over the scroll's first
  20 pt, then switches off once the leaving copy is past the edge, when only
  the gap is under it, so the repeat eases into place unfaded, as Music's
  does. Build 145's ramped off over the scroll's last 20 pt instead, which
  the eased stop stretched into 1–2 s a loop of the arriving first letter
  dimmed by up to 25%; the owner had noticed ("cool was hoping i wouldn't
  have to mention that").
- **Music's title is 20 pt SF Pro** (cap height 14.1 pt); the row's is 17.
  The numbers stay in points, as Apple's code has them.

**What Apple's code says**, found by a research agent in decompiled iOS
builds: iOS 26.1 at github.com/EthanArbuckle/iPhone18-3_26.1_23B85_Restore
(Music.app and its MusicApplication.framework), 18.2 at
EthanArbuckle/iPhone17-1_18.2_22C152_Restore, and the 17.6.1 build above.
- Music's full-screen title and artist are drawn by Music's own `MarqueeView`,
  a fork of MPUFoundation's `MPUMarqueeView` that arrived in iOS 26.0
  (ipsw-diffs). Its defaults, which Music never changes: `marqueeDelay` 3.0
  and `marqueeScrollRate` 30.0. The full-screen player sets `contentGap` 32
  and, as the research read it, fade insets of 24 on each side, where the
  recording shows 20 (above); the mini player, 32 with fades of 8 leading
  and 40 trailing. The fade is one `CAGradientLayer` over the whole view,
  white to clear across each inset with `kCAFilterDestOut`, fixed while the
  text moves under it, and the text is laid out at the leading inset, so it
  rests clear of the fade.
- Each loop is one `CAKeyframeAnimation` on `transform.translation.x`, values
  [0, 0, -L, -L] at key times [0, delay/D, duration/D, 1], with
  `kCAMediaTimingFunctionEaseInEaseOut` as the animation's own timing
  function. Core Animation applies that to the whole animation before its
  segments, which are linear: hence one eased loop, the hold included.
  `duration` is 3 s + (width + gap) / 30, and D is the longest of the title's
  and the artist's, which the title coordinates, so the two lines share a
  loop and the shorter one stops where it runs out. When a loop ends,
  `animationDidStop:finished:` builds the next from that moment, so every
  loop starts with its hold, and the 0–25 ms pause measured above fits it.
- For comparison, from the same decompiles: the Lock Screen's
  `MPUMarqueeView` is linear (Linear by name in 17.6.1 and, by the import
  table, in 26.1), with a 3 s delay, 30 pt/s, a 26 pt gap and 3 pt fades.
  UIKit's private UILabel marquee, which build 120 switched to, has no timing
  function at all: a 1.5 s rest, 30 pt/s, a 40 pt gap and an image mask. No
  setting on that path could ever have eased, which is what the owner saw.
- This is iOS 26.1 code. The owner's phone runs 27.2, and the recording
  agrees with it on everything but the fades. Music's `MarqueeView` is still
  in the 27.0 betas' symbol lists.

`MarqueeLine` now does all of it and is the only scroller: build 145 brought
the eased loop, the 32 pt gap and 20 pt fades, and removed
`SystemMarqueeLines`, LNSystemMarqueeLabel and `ThirdPartyNotices.txt`, as
promised; build 148 brought the shared loop of title and artist, the leading
fade that spares the arriving copy, and the corrected script and numbers.
What's left is the device: a recording of a long title in Ammy's row, run
through the script, should give the same curve, speeds and loop.

## Working with the owner

Limited coding experience — comfortable running commands and reading output,
not writing code. Prefers concise, concrete instructions over conceptual
explanation. Give **one command at a time** and wait for output; stacked
commands hide failures when an early one hangs.

The repo is cloned at `C:\Users\links\Repos\Ammy` (renamed from
`repos\ampresence` on 9 Sept 2026). Edit the files in place.

**Git commands are yours to run.** A Claude Code session has a real shell on the
owner's Windows machine, so `git status`, `git add`, `git commit`, `git log` and
`git push` all work against the clone directly — run them yourself instead of
handing lines over to be pasted, and report what they printed. The same goes for
`.github/workflows/`: it is an ordinary file here.

**Pushing needs the GitHub CLI's sign-in, as of 14 Nov 2026.** Git has no
`credential.helper` configured on this PC any more (most likely lost in the
11 Nov malware cleanup), so a plain `git push` fails with "could not read
Username". `gh` is signed in, and this works without changing any config:
`git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push`.
Setting a helper permanently (`gh auth setup-git`) is the owner's call.

**The hand-it-over rule was Cowork-only, and the reasoning still holds there.**
Under local Cowork the shell is a separate Linux VM whose mount of host folders
does not permit unlink — `git rm`, `git reset --hard`, even `git status` fail
partway and leave a stale `.git/index.lock` blocking the owner's next command.
Under cloud Cowork there is no shell on the machine at all; files are reached
through the desktop app, and `.github/workflows/` is refused outright as a
protected path. In *those* environments: edit with the file tools and hand over
the git lines. Not in a Claude Code session.

Also Cowork-only, and worth keeping for when it applies: "what state is this in?"
can be answered without running anything, because `.git/logs/HEAD` is the reflog,
`.git/logs/refs/remotes/origin/main` records pushes, and `.git/config` holds the
remote URL. Reading those three settled "is the rename committed?" in one call on
8 Sept, against a handoff note that claimed otherwise — but that was a workaround
for having no shell. With one, `git log` is the direct answer and those files are
the fallback.

**Verify, don't assert.** This project has burned several rounds on confident
wrong answers — that Discord couldn't hyperlink activity text (it can:
`details_url`, `state_url`, `large_url`), that a bug was in one place when the
logs hadn't been read yet. Read the file, read the log, check the API. When the
owner says something works, believe them and go look. Also: GitHub's tree and
contents API endpoints have served **stale cached listings** here, showing a
week-old file set as current — fetch `raw.githubusercontent.com` directly
instead of trusting a listing.
