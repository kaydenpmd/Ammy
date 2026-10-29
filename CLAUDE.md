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

**Leftovers on the PC, unchanged from 9 to 27 Oct 2026.** The old installed relay
(relay.py, its `.env`, `relay.log` and `ammy-uptime.log` in `C:\Users\links\Python
Scripts`) and the disabled `Ammy Relay` logon task were still there. They are
obsolete, not a rollback: never enable the task, which would contend with Issun
for port 8787, and removing them is the owner's call. The tunnel was still
live too; see "Funnel is the only endpoint" under Where things stand. The
installed Issun, build 38 through all of that, is build 43 since 29 Oct 2026
(`/version`), installed at the owner's yes, with build 38 kept beside it as
`Issun.exe.b38.bak`. It has the new icon, and its tray hint and new-key notice
no longer name Ammy. Updating stops the live receiver for a few seconds, so get
a yes first; the procedure is in Issun's CLAUDE.md, "Updating the installed
copy".

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

So the subtitle and description in `source.config.json`, the landing page in
`public/index.html`, `NSAppleMusicUsageDescription` in `project.yml`, and the
app's own UI all stay receiver-agnostic. Naming Discord in those places states a
requirement that does not exist, and it has already had to be undone once —
18 Sept 2026, after the first listing pitched Discord Rich Presence, a Windows
relay and a Discord application of your own, which is one receiver's setup
rather than a description of this app. The UI has always had this right on
purpose: the field is called **Endpoint**, not Relay, because whether the
address forwards, renders or files what it receives is none of the app's
business.

`README.md` and this file are the other half of the rule. They document the
Discord receiver, which is genuinely what they are about, and they go on saying
so — the fix is never to strip accurate Discord information, only to move it
from "what Ammy is" to "what the receiver does".

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
`AppIcon.png`. Not yet seen on a device.

## Layout

```
project.yml                          XcodeGen spec — no .xcodeproj is committed
.github/workflows/publish-source.yml On push to main: build, GitHub Release, source.json
.github/workflows/build-ipa.yml      Called by the above; unsigned IPA + simulator build
scripts/build_source.py              Regenerates public/source.json
scripts/make_icon.py                 Draws the app icon, like Albums' script of the same name
source.config.json                   AltStore listing metadata (user-facing copy)
public/                              Cloudflare Pages site: landing page, source.json
PUBLISHING.md                        One-time setup for the AltStore source
Ammy/
  AmmyApp.swift                      SwiftUI entry point + settings screen
  PresenceController.swift           Wires playback changes to pushes; failure announcing
  NowPlayingMonitor.swift            MediaPlayer observation; store ID + cover art
  PresenceRelay.swift                HTTPS client for the endpoint; PushOutcome
  KeepAlive.swift                    Silent audio to survive backgrounding
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

**iOS app** — the Status section shows a **Version** row, e.g. `1.0 (7)`. The
build number is the count of commits reachable from the built commit (`git
rev-list --count HEAD` in `build-ipa.yml`), and the artifact is named to match:
`Ammy-1.0-b7-a1b2c3d.ipa`. Matching numbers means the phone is running the build
you think it is. `MARKETING_VERSION` in `project.yml` is the only version number
a human sets; the build number climbs on its own.

## Gotchas already paid for — don't rediscover these

**The large title jitters on collapse, and the code is not wrong.** Scrolling
down far enough to collapse the navigation title renders one frame at the wrong
scroll offset — measured at up to 29px in the wrong direction, then a crawl of
1px per frame for about 13 frames. Scrolling *up* to expand is clean every time;
the defect is direction-specific. It appeared in build 39, the commit that first
put the Start button in a bottom safe-area bar, and it shows on a 60Hz
home-button device.

Everything involved is the sanctioned path. `safeAreaBar(edge: .bottom)` is what
iOS 26 added for bottom content without a tab bar or toolbar; `.glassProminent`
and `.buttonSizing(.flexible)` are stock; a large title on a `Form` is the
default. No published report matches the combination.

**Decided 11 Sept 2026: leave it, and let a future iOS fix it.** Working around
an OS defect means carrying the workaround long after the defect is gone, and
every alternative costs something real — dropping the large title, or taking the
button out of the safe area and losing the scroll edge blur beneath it. The
trade accepted here is a visible cosmetic glitch on older hardware.

Ruled out, so none of it is worth re-testing: the bar itself does not move (zero
pixel difference across a collapse); the content never reverses direction
mid-gesture across 32 gestures; the title never animates while the content is
still. Frame drops measured ~48fps effective during scrolling, but that is partly
the screen recording itself and is not the cause.

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

The untried experiment, if this is ever picked up again: enlarge the bottom inset
*without moving the button* — `.padding(.top, 72)` on the bar's content — and
re-measure. If the jump scales with the inset, the inset height is the trigger,
and that is the finding worth putting in a Feedback report.

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
check-in history is `%LOCALAPPDATA%\Issun\uptime.log` (relay.py's history
merged in ahead of its own), and its window's Diagnostics section shows the
summary that `python relay.py --summary` used to print.

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
after an explicit track, and the push carries `explicit: true`. Since build 120
there are two copies of it, so a change to the E goes in both: on the UIKit
marquee path it is a text attachment at small symbol scale
(`SystemMarqueeLines.titleText`, `UIImage.SymbolConfiguration(font:scale:
.small)`), and on the `MarqueeLine` fallback (`fallbackLines`) it sits inline
in the title's `Text` with `.imageScale(.small)`. **It's just the symbol after a space, in the title's own
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
on a device. That question applies only to the fallback; the UIKit path sets
the scale on the symbol itself.

**Only ever `true`**: `MPMediaItem.isExplicitItem` is a plain
Bool, and its `false` covers an unrated track as well as a clean one, so the
phone can't honestly claim "clean". Receivers treat an absent flag as "don't
know"; Issun then asks the exact store-ID lookup's `trackExplicitness`, never
fuzzy search. `PresenceController` compares `explicit` beside `Track.key` so a
switch between a song's clean and explicit editions, which share title, artist
and album, pushes at once rather than at the next heartbeat.

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

- **Artwork 57 pt**: measured on the Lock Screen (56.8). No documentation;
  Apple's iOS 26 UI kit has Control Center's player (52 pt art) but no Lock
  Screen one.
- **Title and artist the same size**, one line each, scrolling when too long:
  Headline and Body, both 17 pt per the HIG's type table. The Lock Screen
  measures 17/17, and the UI kit gives Control Center 14/14.
- **Equal padding**: the vertical row insets are set to the leading inset the
  system chose, which is measured at run time (16 pt on an SE, 20 on a Pro Max;
  no API reports it). Uses iOS 26's `listRowInsets(_:_:)`.
- **Concentric corner**: section radius (26 pt, measured on two phones; no API)
  minus that inset: 10 pt on an SE, 6 on a Pro Max, never below 6. A List cell
  doesn't give ConcentricRectangle a container shape (developer forums thread
  798726), so it's done by hand. A measured inset outside 8–40 pt is ignored.
- **Other iPhones**: the inset, the corner and the pixel size of the artwork
  follow the device. The 57 pt artwork and the 26 pt section radius are
  believed constant: the radius is confirmed on an SE and a Pro Max, the
  artwork only on the SE.
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
- **Scrolling** has been set to use UIKit's own marquee since 15 Oct 2026
  (build 120): the one built into UILabel, which Apple keeps private and
  publishes no timing for. Whether it is what actually runs on the owner's
  phone is unconfirmed. The owner had asked for the scroll to ease into a stop
  like Music's, and on build 120 reported "there is no easing visible". So
  either UIKit's marquee is linear (it is the one tvOS uses for focused text,
  and may never have been Music's) or `SystemMarqueeLines.available` was false
  and the row fell back to `MarqueeLine`. The code comments claim more than is
  known: `SystemMarqueeLines` calls UIKit's marquee the one "Apple's apps use"
  and "the only exact match", and `MarqueeLine`'s says UIKit's runs on iOS 26
  and 27. **Unfinished: Open work item 10.** `SystemMarqueeLines` turns UIKit's
  marquee on through
  LNSystemMarqueeLabel (MIT, pinned to 0.1.2 in `project.yml`, notice in
  `ThirdPartyNotices.txt`). LNPopupController, an open-source replica of
  Music's player, offers the same label as an option and defaults to it only
  on Mac Catalyst, so the path is little used on iPhone. Each line scrolls on
  its own and a new song restarts both: the package's line syncing is left
  off, because in 0.1.2 it never switches on (its +load runs before its C++
  statics) and could stall a line if it did; the comment on
  `SystemMarqueeLines` has the detail. Stopped in the background, off under
  Reduce Motion. If an iOS release drops the private properties, the row falls
  back to `MarqueeLine`, the hand-made version with LNPopupController's linear
  numbers (2 s rest, 30 pt/s, 50 pt gap, 10 pt fade), instead of crashing.
  **Not yet seen on a device:** whether the E still sits at cap height in
  UIKit's text, and VoiceOver reading the row.

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
- **The Discord application stays named `Apple Music`**, not Ammy or Issun. Its
  name is the text after "Listening to", and that should describe the source,
  not the bridge.
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
receiver. On 9 Oct 2026, and again on 27 Oct, it was still live in two places: the `cloudflared`
Windows service was running and its address still answered with Issun's
`X-Ammy-Relay` header, and Issun's **Public address** setting still held it
(imported from relay.py's `.env` on 22 Sept), which overrides the Tailscale
name for the window's endpoint and for cover URLs sent to Discord. Finishing it
is the owner's: clear Public address in Issun's Settings, remove the
`cloudflared` service from an elevated shell, and delete the tunnel's public
hostname and DNS record in the Cloudflare dashboard. The token lives in the
service's registry `ImagePath` (token installs have no `config.yml`), and
refreshing it in the dashboard does *not* drop a connector that is already
connected; removing the service does.

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

**Still unexplained: what ends a run.** Every death recorded since the fix has
carried `engine=yes want=yes` — a healthy audio engine — with no correlate in any
signal collected. It is now a roughly once-a-day event rather than an hourly one.
Whether that is worth chasing further is a judgement call, not an open bug.

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
- **Each user needs their own Discord application**, which is a five-step detour
  of its own. Note the application's *name* is the "Listening to" text, so it
  stays `Apple Music` — that string describes the source, not the bridge. Fine
  for one person; think hard before it is on hundreds of profiles.
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
from an `onGeometryChange` on the `NavigationStack`. That is outside the bar
because reading the safe area inside a `safeAreaBar` is circular; it is
`onGeometryChange` rather than a key-window read because iPad rotates and
resizes, and rather than a `GeometryReader` because that would take over the
layout beneath it. The bar pads `.padding(.bottom, edgeGap - bottomSafeArea)`
with `edgeGap = 21`, which pins the button 21pt above the true screen edge on
every device, no clamp needed. System bars don't stop at the top of the
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

**10. Long titles should ease into a stop, as Music's do — waiting on a screen
recording.** Asked 15 Oct 2026: "can you make the long-title scrolling ease
into a stop like what happens in apple music if that's easy to match exactly".
Apple publishes no timing for Music's marquee, and LNPopupController's default
marquee on iPhone (cbpowell's MarqueeLabel) is linear, which is where
`MarqueeLine`'s numbers came from. The owner then suggested UIKit's private
marquee ("how about just lnsystemmarqueelabel"); it shipped in build 120, and
the owner reported "there is no easing visible in build 120", the same day.

The next step was asked of the owner twice on 15 Oct 2026, before and after
build 120, and had no answer by 27 Oct: a screen recording showing a long title
scrolling in Music through at least one full loop until it rests, then a long
title scrolling in Ammy. Measure Music's curve, speed, pause and gap frame by
frame with ffmpeg (on PATH here, from winget's yt-dlp.FFmpeg package), using
each frame's timestamp from `ffprobe` rather than assuming 60 fps, since screen
recordings drop frames (see the large-title note in Gotchas). Ammy's half shows
which scroller build 120 ran: `MarqueeLine` moves at exactly 30 pt/s with a
50 pt gap. The app also logs it once per launch in the phone's system log
(`Logger`, subsystem `com.local.ammy`, category `marquee`: "UIKit's marquee" or
"UIKit's marquee is missing; using MarqueeLine"), but reading that needs a
device-log tool, and none is set up here. Then build the measured timing into
`MarqueeLine`, and if UIKit's marquee adds nothing, remove `SystemMarqueeLines`,
the package in `project.yml` and `ThirdPartyNotices.txt` in the same release,
as promised to the owner.

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
