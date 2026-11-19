# Context for Claude Code

**This file holds the current state and the rules. The story of how they came about is in `HISTORY.md`**: every measurement, lab, correction and rejected approach up to 15 Nov 2026, under the section names used here. Read the matching section there before redoing anything this file calls settled, and before reopening a decision.

**Keeping it that way.** When something changes, edit this file to say what is true now, in as few lines as it takes, and write the story (what was tried, measured, seen or rejected, with dates and evidence) at the end of `HISTORY.md` under a dated heading. Rules and current facts here; narrative there. Code comments that cite "CLAUDE.md" and a section name mean `HISTORY.md` when the section is only a pointer here.

**Check `git log` and `/version`, not this file, for what has shipped.** Documented state decays in whichever direction you aren't looking.

## What it is

Apple Music on iPhone → Discord Rich Presence on a Windows desktop.

```
iPhone ──https──▶ <machine>.<tailnet>.ts.net (Tailscale Funnel) ──▶ Issun, 127.0.0.1:8787 ──IPC──▶ Discord desktop
```

Everything is called **Ammy**: Home Screen name, Xcode target, scheme, source folder, bundle ID `com.local.ammy` (renamed from AMPresence on 8 Sept 2026).
**Don't change the bundle ID again**: iOS treats it as a new app, every user re-pairs, and nothing displays it.

The receiver is **Issun** (github.com/kaydenpmd/Issun, cloned at `C:\Users\links\Repos\Issun`), and it is the only one. Don't redesign it. Its CLAUDE.md is the reference for its code, settings, logs and the Discord-side lessons (playhead anchor, rejected payloads, IPC).

Retired on 25 Sept 2026, by the owner: relay.py ("kill relay.py it's obsolete"; last copy `git show 3b7875c:bridge/relay.py`, no fallback) and kaydenpmd.net as an endpoint ("stop using kaydenpmd.net across this entire thing in favor of tailscale"). The endpoint is Tailscale Funnel only. The AltStore source stays on `apps.kaydenpmd.net` ("altstore can stay using my site").

**Leftovers on the PC, the owner's to remove:** the old relay in `C:\Users\links\Python Scripts` and the disabled `Ammy Relay` logon task (never enable it; it would fight Issun for port 8787), and the `cloudflared` Windows service, still running on 4 Nov 2026 (remove from an elevated shell; its token is in the service's registry `ImagePath`). Never offer the old tunnel as a way to reach the receiver.

## Why it's built this way

Discord has **no Rich Presence SDK on iOS**. The sanctioned path is a local IPC socket (`\\.\pipe\discord-ipc-0`) that only the desktop client exposes. Setting presence from the phone would mean a Gateway WebSocket with a user token: self-botting, against ToS, accounts terminated. So the phone never talks to Discord; it POSTs JSON to the receiver, which uses IPC. **Any change that moves Discord communication onto the phone is wrong.** The cost, accepted: presence needs the PC awake with Discord open.

## What Ammy is, in anything a user reads

**Ammy is a sender**: it reads Apple Music's now-playing state and POSTs it to an HTTPS endpoint the user chooses. It's built to pair with Issun and works with anything that accepts the POST.

- `public/index.html`, `NSAppleMusicUsageDescription` in `project.yml` and the app's UI stay **receiver-agnostic**: never name Discord. The UI says **Endpoint**, not Relay.
- The listing's subtitle and description, the README and the landing page's prose are the owner's to write (3 Nov 2026). Until then: no subtitle, empty `localizedDescription`, README is the name only, landing page has its buttons and facts from `source.json`. Don't fill them in.
- All interface text is the owner's too (global CLAUDE.md, the wording page).
- Check non-prose surfaces: the listing's accent colour is system blue `#007AFF`; it was once Discord's blurple and carried the old framing.
- This file documents the Discord receiver, accurately. The rule is about what Ammy is, not about removing Discord facts.

## The icon

An album cover being sent: Albums' black tile with two waves leaving it in Albums' greys, black on white, plus white-on-black dark and tinted versions, drawn by `scripts/make_icon.py`. No music note, no receiver named: "ammy's just represents music, and issun's just represents chat". Issun's icon is the other half (the waves arriving at a speech bubble), white on Discord blurple since 14 Nov 2026.

`public/ammy-icon.png` is a copy of `AppIcon.png`, listed as `ammy-icon.png?v=2`. **Bump `?v=` whenever the icon changes**: SideStore caches by address.

## Layout

```
project.yml                          XcodeGen spec — no .xcodeproj is committed
.github/workflows/publish-source.yml On push to main: build, GitHub Release, source.json
.github/workflows/build-ipa.yml      Called by the above; unsigned IPA + simulator build
scripts/build_source.py              Regenerates public/source.json
scripts/make_icon.py                 Draws the app icon, like Albums' script of the same name
scripts/measure_marquee.py           Times a scrolling line in a screen recording
source.config.json                   AltStore listing metadata (user-facing copy)
public/                              Cloudflare Pages site: landing page, source.json
PUBLISHING.md                        One-time setup for the AltStore source
HISTORY.md                           How everything got this way
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
  CodeScanner.swift                  VisionKit QR scanner for the endpoint and key
```

## Telling builds apart

- **Receiver**: `GET /version` answers `issun <version> (<build>)`, and every response carries it in `X-Ammy-Relay`. Never write the current version here; ask `/version`.
- **iOS app**: the **Version** row, e.g. `1.0 (7)`. The build number is `git rev-list --count HEAD` of the built commit; the IPA is `Ammy-1.0-b7-a1b2c3d.ipa`. `MARKETING_VERSION` in `project.yml` is the only number a human sets.

Receiver routes: `POST /now-playing` (the phone writes; 204 on success, 401 key, 404 path, 400 bad JSON), `GET /now-playing` (a projection, never the raw push, never triggers a lookup), `/health` (exactly `ok`; Shortcuts test for it), `/status` (`alive`/`stale`), `/diag` (the phone's last self-report, authenticated), `/art/<hash>.jpg` (open, because Discord's CDN can't send the key).

## The push

What every push carries that a receiver relies on:

- `seq`, milliseconds since epoch (not a counter, which resets on relaunch). The receiver drops a push whose `seq` isn't newer, and logs it.
- `app_uptime_s`, `app_version` and `diag` (Diagnostics, below). A push whose uptime fell further than its `seq` did comes from a new process and supersedes the old session (Issun's `PhoneState`).
- `"activity_name": "Apple Music"`, fixed in `PresenceRelay.push()` and changeable nowhere in the UI, by the owner's choice (14 Nov 2026). Issun sends it as the activity's name: "Listening to Apple Music". It names the player Ammy reads, not a receiver.
- `store_id` (`playbackStoreID`), `artwork_b64` once per track, `explicit: true` (only ever true), `live: true` with `duration: 0` for stations.
- `playing: false` pushes are check-ins too: a paused app keeps checking in.
- Key header `X-Relay-Key` (`X-Relay-Secret` still accepted).

## Rules from bugs already paid for

Each has its full story in `HISTORY.md` under "Gotchas already paid for" or the named section.

**The bottom bar.**
- The bar is a `safeAreaBar` on the **`NavigationStack`, not the Form**. On the Form it makes the large title jump on collapse (a SwiftUI defect; lab on `jitter-lab`, Feedback report drafted there, waiting to be filed from the owner's account). Seen fixed on the owner's SE, build 150.
- Because a stack doesn't pass its bar's inset to lists (FB23732628), the page gets the bar's room as **UIKit** safe area: `BarRoom`, a view controller inside the page, sets `additionalSafeAreaInsets.bottom` on the view controller the navigation controller holds for the page, from the window's own inset up to the bar's top edge, the keyboard included while it's up (`barRoom`). Since build 208; builds 158–201 used `.safeAreaPadding(.bottom, barHeight)`, the same room for the Form but inside SwiftUI only. Not `contentMargins`, which replaces the list's own 20 pt instead of adding to it.
- The page carries a copy of the bar while sliding to and from History (`PageTransitions`, `viewWillDisappear` to `viewDidAppear`); the stack's bar steps aside without animating. The copy lays out inside the page's safe area, which ends at the bar's top, so it's offset down by `barHeight`. **Don't fade the stack's bar**: tried in builds 150–154, looked worse.
- `bottomSafeArea` is read from a `Color.clear` background with `.ignoresSafeArea(.keyboard)`, so it stays 0 or 34 while the keyboard is up. The bar pads `edgeGap` (21 pt) above the screen edge, or above the keyboard when it's up. Reading it without ignoring the keyboard hid the bar behind it from build 77 to 172. iOS leaves the keyboard out of screenshots while the secure Key field is focused; trust frames.
- `edgeGap = 21` and the bar's 21 pt sides are the floating tab bar's: on iOS 27 a full tab bar's outline sits 20.5 pt from the sides and 21 from the bottom at every iPhone width, and Ammy's bar lands on it to the pixel (design library `apple/ios-bottom-bar-widths/`, 18 Nov 2026). They're measured numbers, since the system exposes no tab bar inset. Bottom toolbar items are a different family at 27.5 pt; don't mix the two. Apple's wide Continue button on its Welcome sheets is a third: 38 pt from the sides and the bottom, 52 pt tall. Ammy's bar was built there in the `wide-bar-lab` lab (19 Nov 2026) and not adopted: on an SE the page's rows show around the narrower button, and Apple's wide button doesn't ride above the keyboard, which Ammy's bar has to. With the keyboard up the bar sits 21 pt above it; Apple's bottom search bar, the one thing it floats there, sits 10. `.padding(.horizontal)` with no argument is 16 pt, which is wrong.
- **Don't draw a background behind the bar.** `safeAreaBar` applies the system's scroll edge effect, which iOS 27 changed and Ammy followed for free.
- Rejected, not worth retrying: `safeAreaInset`, `contentMargins` with an overlay, `UIScrollEdgeElementContainerInteraction`, a `.bottomBar` toolbar.
- **Picture in Picture rests above the bar** (build 208). iOS rests PiP 10 pt above the bottom safe area the app reports to SpringBoard (`primaryWindowOverlayInsets`; 24 pt on iPad), and only UIKit's safe area counts: tab bars, bottom toolbars and `additionalSafeAreaInsets`, never `safeAreaBar` or `.safeAreaPadding`. `BarRoom` is what reports the bar, so whatever reserves the bar's room has to stay in UIKit's safe area. With the keyboard up the room includes the keyboard, so PiP rests above Stop and Restart too; over History, which has no bar, it drops to the bottom (HISTORY.md, 18 Nov 2026; design library `apple/ios-pip-placement/`).

**The main screen.**
- No section headers under the large title (the owner chose "Option 1", 2 Nov 2026, build 158; HISTORY.md "No section headers on the main screen").
- VoiceOver reads the song card as "Now Playing, <title>, <artist>": `accessibilityLabel(content:)` straight after `.accessibilityElement(children: .combine)` (build 164).
- Glass button styles are already interactive; don't add `.glassEffect(.regular.interactive())`. Stop (`.glass`) and Start/Restart (`.glassProminent`) sit in a `GlassEffectContainer` and morph through `glassEffectID`. **When a question is about how something feels, build it and touch it.**

**Playback.**
- `currentPlaybackTime` reports the previous song's position for a second or two after a change. `PresenceController` re-reads it at send time and sends a correction 2.5 s after every change. Don't remove either.
- Live stations have a NaN position. Send `duration: 0` and `live: true`; never the real length with position 0 (the bar snaps back every heartbeat). `PresenceRelay` checks `isValidJSONObject` first, because `JSONSerialization` raises an Objective-C exception on NaN that `try?` can't catch.

**The keepalive.**
- **Never conclude the keepalive is off.** `running` means "we want silence"; a failure leaves it true and a 10 s timer retries. Handled stops: an interruption, a media services reset, a configuration change, a failed `resume()`.
- **Never rely on `.ended`**: iOS often doesn't deliver it (`int=12/4` once). The retry loop, the 10 s `engine.isRunning` check and `keepAlive.verify()` on every push all stay.
- A refused `engine.start` makes the next try build a fresh engine (build 167). Since build 181 `.began` itself tries a restart at once and at +1 and +3 s (`KeepAlive.restartAfterBegan`).
- No background-task hold (parked 11 Nov 2026; the lab found ways it gets the app killed outright). Revisit only with journal evidence, and then with the guards in HISTORY.md, "The keepalive hold, parked".

**Notifications.**
- `requestAuthorization` must be called: `add()` on an unauthorized center succeeds and delivers nothing. `PresenceController.start()` does it.
- `SilenceWatchdog` is inverted on purpose: a notification 15 minutes out, re-scheduled on every successful push, so it fires only if Ammy stops. It survives force quit and power-off. Don't replace it with death detection.

**Failures.**
- **Every failure path logs.** Silent failure is this project's recurring bug.
- Every terminal failure is a `FailureNotice` through `fail()`: status row to Disconnected, recorded in `EventLog`, announced as a popup when the app is active and a notification otherwise (`ammy://notify` asks for the notification). The status row shows state only, never a reason.
- A notice has a `summary` (History's label) and an `explanation` (likely cause and what to check). When adding a case, write both, about "the receiver" and "the address", never a product.
- `secureConnectionFailed` usually means Funnel couldn't reach the PC, not a certificate fault.

**Build config.**
- No `.xcodeproj`; CI generates it with XcodeGen. `SWIFT_VERSION` is a language mode: 4.0, 4.2, 5.0 or 6.0.
- Don't transcribe config from screenshots. Paste values; print `.Length` to check a secret.

## Diagnostics

Issun's log is `%LOCALAPPDATA%\Issun\issun.log`, its check-in history `%LOCALAPPDATA%\Issun\uptime.log`, and its window's Diagnostics section shows the summary. **Read them from PowerShell, not the Bash tool**, which shows a stale sandboxed copy.

The app can't report its own death, so every push carries a `diag` snapshot, and the receiver prints the last one onto the "phone stopped checking in" line:

```
phone stopped checking in  last seen 00:39:33  last state: engine=yes want=yes
route=BluetoothA2DPOutput resumes=1 fails=0 heals=0 cfg=0 routechg=1 int=0/0
mem=19MB state=background lpm=no thermal=fair appup=3554s devup=31067s
```

- `engine` (`AVAudioEngine.isRunning`) and `want` (what `KeepAlive` believes) disagree only when the keepalive is dead.
- `int=began/ended`: began ahead of ended is a missed `.ended`.
- `appup` is wall time since launch, so on a death line it's that process's lifetime. `devup` stops while the phone sleeps, so `appup` > `devup` is normal.
- `mem` is `phys_footprint` (what jetsam measures). Memory, Low Power Mode and thermal state have each been ruled out as causes.

**The phone's journal** (`KeepAliveJournal`, since build 167): every keepalive event goes to `keepalive.log` in Application Support (400 lines), and every 10 s tick stamps `keepalive.alive`. The next launch sends the previous run's last 25 lines (`prev_tail`) and stamp (`prev_alive`) until a push lands, and Issun (build 48 on) prints them once as `[keepalive] previous run ...` and `[keepalive] journal: ...` lines. Other fields: `fail_stage`, `fail_code`, `fail_run`, `fail_run_max`, `down_s`, `secs_since_fail`, `int_on_resume`, `int_reason`, `secs_since_began`, `secs_since_ended`; `last_error` ends with the code and its four characters (e.g. `[2003329396 'what']`).

**Killed or unreachable?** Both are silence to the receiver. Two fields decide it on the gap line: `app_uptime_s` (same process if it advanced by about the gap) and `pushfail=consecutive/total` with `offline=Ns` (the app knew it was failing). Verdicts read "the path failed, not the app", "suspended, no pushes failed", "stopped on the phone", "it died", or, in Issun's code since 15 and 16 Nov 2026, "updated, <old> -> <new>" when a new build ended the gap and "the phone restarted, devup <old>s -> <new>s" when a new boot did. A death line always shows `pushfail=0`; that's expected.

- **A gap isn't proof iOS killed the app.** Rule out the phone being off and the app not reopened after a reboot first. **If the new process reports a smaller `devup` than the death line (on its next line, or in `/diag`), the phone restarted**: `systemUptime` goes back only on a reboot. Issun builds before 16 Nov 2026 don't check this and write "it died"; 23 of the 75 up to that date were restarts. `local/reboot_census.ps1` sorts every line.
- Discount too the three wrong lines, where the next process had started before the gap (14 Sept 2026 14:59, logged twice; 16 Oct 2026 21:56:52; 8 Nov 2026 16:11:50), and any "it died" whose stamp names a newer app build than the line before it: an install ended that process or that gap (19 of the 75; HISTORY.md, 15 Nov 2026).
- **Don't split the log per version.** Lines are stamped `[issun <version> / app <build>]`; group them later.

## Artwork

1. **Catalog ID** (`store_id`): exact lookup. The normal path.
2. **JPEG from the phone** (`artwork_b64`), for tracks with no catalog ID: cached under a hash, served at `/art/<hash>.jpg`. Never yet run for real.
3. **Fuzzy iTunes Search**: best effort, floor 0.35 (`ArtMinScore`, locked by the owner). An `[art] weak match` line means the phone sent no store ID.

The phone sends the JPEG once per track, and Issun reuses the file on disk. When `MPMediaItemArtwork.image(at:)` returns nil for a streamed song, `NowPlayingMonitor` tries the artwork's `bounds` size, then iTunes Lookup by store ID (device region, once per track, 60 s back-off, dropped if the song changed). That lookup is the only request Ammy makes to anything but the endpoint.

## The explicit badge

The title's `Text` ends with a space and `e.square.fill` at `.imageScale(.small)`, in the title's own colour, nothing more (the owner's choice). The push says `explicit: true` only: `isExplicitItem`'s false can mean unrated. `explicit` is compared beside `Track.key`, so switching between clean and explicit editions pushes at once and restarts the marquee.

## The Now Playing row

Matched to the Lock Screen's player; the measurements and sources are in HISTORY.md under "The Now Playing row's proportions" and Open work item 10.

- **Artwork 57 pt**, a constant because the Lock Screen's is a literal (re-measure after major iOS releases). Covers are downsampled with ImageIO to the drawn pixels, and fitted, not cropped. Nothing playing: a plain `tertiarySystemFill` square.
- **14 pt** from the artwork to the card's side, top and bottom, and 12 pt to the text, on every iPhone. The row pads by the difference from the list's measured insets, read once they've been still for 150 ms. Not `listRowInsets`: a zero vertical one had no effect.
- **Corner**: 26 pt (the section's measured radius) less the average of the measured side and top gaps, never below 6. 12 pt with 14 and 14.
- Title Headline, artist Body, 17 pt each, one line each.
- **Scrolling** (`MarqueeLine`), Music's own: hold 3 s, scroll at 30 pt/s until the repeat takes the text's place, the whole loop through ease-in-ease-out; 32 pt gap; 20 pt fades, the leading one only over the copy that's leaving. Title and artist share one loop, sized by the longer travel. Stopped in the background, off under Reduce Motion. `scripts/measure_marquee.py` measures a recording.

## Clickable presence

| Field | Opens from | Source |
|---|---|---|
| `details_url` | the title line | `trackViewUrl` |
| `state_url` | the artist line | `artistViewUrl` |
| `large_url` | the cover art | `collectionViewUrl`, with `?i=` stripped |

Filled **only from the exact store-ID lookup, never fuzzy matching**. One link per artist isn't possible over RPC (tested 14 Nov 2026; design library, `discord/rich-presence-card/`). The album line (`large_text`) stays off, the owner's choice.

## Build and deploy

Push to `main` runs `.github/workflows/publish-source.yml`, unless the push touches only `**.md`, `public/**`, `scripts/**` or `source.config.json`. It calls `build-ipa.yml` on `macos-26`, which builds unsigned (SideStore re-signs) with build number `git rev-list --count HEAD`, then cuts a GitHub Release `v<version>-b<build>`, regenerates `public/source.json` and commits it back; Cloudflare Pages deploys it to `apps.kaydenpmd.net`. `build-ipa.yml` by hand builds without releasing.

**Pushing to main is releasing.** The newest commit's message, minus trailers, becomes the release notes and SideStore's What's New. Get the owner's OK on that text first, and write each paragraph of it as one line: the GitHub Release shows the message as written. `build_source.py` joins a paragraph's lines into one for SideStore (`reflow()`, 18 Nov 2026).

Albums is in this source too: its CI pushes `public/source.json` here, so `main` can move under you (`PUBLISHING.md`). The repo is public because macOS minutes bill at 10× on private repos.

Install path is **SideStore** (needs only iTunes); AltStore works for those who have it, but nobody is sent to get it. Free accounts expire in 7 days; a paid account makes it 365 for that account only.

## The receiver on the PC

Issun, at `%LOCALAPPDATA%\Programs\Issun\Issun.exe`, started in the tray from the HKCU Run key, settings in `%APPDATA%\Issun\settings.json`. Since 12 Nov 2026 it has been replaced often by local publishes of Issun's `main` (`tools/install-local.ps1` there); each earlier build is kept beside it as `Issun.exe.b<build>.bak`. **Updating stops the receiver for a few seconds, so get a yes first**; the procedure is Issun's CLAUDE.md, "Updating the installed copy".

- **The key** comes from Issun (first run or **New key**) and must match the app's **Key** field.
- Issun builds in one Discord application ID (the owner's, named Issun), so nobody makes their own. Its name shows only when a source sends no `activity_name`.
- **Public read** (`PublicRead`, off by default) serves `GET /now-playing` with no key and with CORS.
- Listens on **127.0.0.1 only**; Funnel is the only way in. Issun's address is Tailscale's: its Public address override was removed (build 127).
- Gap logging exists to answer whether iOS kills the app; it separates phone-silent from receiver-down so a PC reboot isn't counted as a death.

## When Ammy can't connect

1. Check Issun answers locally (`127.0.0.1:8787/health`).
2. Look up the ts.net name with DNS-over-HTTPS (Google, Cloudflare). **NXDOMAIN → toggle Funnel**; the record comes back in seconds:
   ```
   tailscale funnel --https=443 off
   tailscale funnel --bg --https=443 localhost:8787
   ```
   Resolvers can cache the NXDOMAIN for five minutes; on the phone, Airplane Mode on and off clears it.
3. Name resolves but check-host.net still gets "Broken pipe" after a minute or two → the 24 Sept failure (Funnel stops serving while saying "Funnel on"); a reboot fixed it.

**Test from outside, never from the PC**, whose lookups of its own name are answered with the tailnet address. check-host.net agrees with the phone; Claude's web fetcher has got through when nothing else could, so don't trust it alone. Funnel setup needs `--bg` (or it dies with the shell), MagicDNS, HTTPS certificates and the `funnel` attribute. Turn off "Auto-generate from OS hostname" so renaming the PC doesn't move the address.

## Where things stand

As of 16 Nov 2026. Ammy 184 is on the owner's phone (installed 14 Nov 2026); Issun is a local build of its `main` (ask `/version`).

**Deaths.** Since 1 Nov 2026: seven on the same boot, the last three on the night of 13–14 Nov (build 177), and eight phone restarts, which end the app too and leave it closed until it's opened. The phone's journal (14 Nov 2026) showed most deaths follow an interruption that freezes the app before it can restart the silence. Build 181's restart at `.began` answers that, and on 15 Nov 2026 the journal showed it working on the phone: `engine stopped, trying`, `playing again after 0 failed tries, down 0s`, then `still playing` at +1 s and +3 s.
184 hasn't died: its first process ran 42.6 hours, through 31 interruptions, until the phone restarted at about 22:36 on 15 Nov 2026.

**Next: keep reading Issun's log on 184.** On a death line, check `devup` first. A death's `[keepalive] journal:` lines show how far it got. If deaths end between `.began` and a restart's outcome, that's the evidence for a short hold, built with the lab's guards. Still unknown: what the owner was doing on the phone at 23:58, 01:19 and 01:47 on 13–14 Nov 2026, which would name the interrupter.

**Not yet seen on a device**, as of the notes. Each of these was checked only in the simulator or not at all:
- the bar above the keyboard (fixed 12 Nov 2026), and iPad's floating and hardware keyboards
- Picture in Picture resting above the bar (build 208); the iPhone simulators only show PiP on device types given the iPad's PiP flags
- History's 36 pt of room at the foot of the page (build 158)
- the copy of the bar sliding with the page to History (build 156)
- VoiceOver's "Now Playing" (build 164), not yet heard
- the explicit E at small scale, and whether `isExplicitItem` is set for streamed catalog tracks
- the shared title and artist marquee (build 148): record a long title in Ammy's row and run `scripts/measure_marquee.py`
- QR scanning, and scanning Issun's code
- the new icon in SideStore
- the bar's distance from the edge by touch, on a Face ID phone and the SE
- the uploaded-JPEG artwork path

## Scanning a receiver's QR code

The **Scan QR Code** row under URL and Key opens VisionKit's scanner (`CodeScanner.swift`). A code holding `{"endpoint": "...", "key": "..."}` fills whichever fields it carries and closes the sheet. A code with neither, or a non-https endpoint, is ignored and logged. Plain JSON, not a link, so neither app names the other. Hidden where VisionKit can't scan. `NSCameraUsageDescription` is the owner's wording and must match `source.config.json`'s `appPermissions`.

## Open work

1. **Shippable to others.** A stranger needs three accounts (Discord, Tailscale, Apple) and about eight steps; autostart is Windows-only. Issun is the self-provisioning receiver.
2. **Shortcuts relaunch automations**: rebuild only if the app still dies. Recipe in HISTORY.md, Open work item 2: `Get Current App` first, `GET /status` with the key, if `stale` and not locked, `Open App [Ammy]` then `Open App [Current App]`. Triggers are per-device and can't be shared. `ammy://notify` opens the app like `Open App`, but a connection failure arrives as a notification.
3. **`Is Running` is unverified.** Test it against a real death, not a force quit.
4. **Distribution, decided 10 Sept 2026; don't reopen without new facts.** An unsigned IPA from CI, installed however people like. Floor iOS 26 (`safeAreaBar`). The App Store is impossible (silent-audio keepalive); AltStore PAL is the wrong audience; ad-hoc is possible for a small circle. The only thing that removes the problem is a different sender: Apple Music's API reports recently played tracks with no iOS app, at the cost of no progress bar and lagging updates.
5. **tvOS**: the reading side ports (tvOS 14+); whether the keepalive survives is unknown. Test with a stub target.

## Working with the owner

Limited coding experience: comfortable running commands and reading output, not writing code. Concise, concrete instructions. Give **one command at a time** and wait for output.

The repo is at `C:\Users\links\Repos\Ammy`. Edit files in place, and **run git yourself** (status, commit, push) and report what it printed; `.github/workflows/` is an ordinary file here.

**Pushing uses the GitHub CLI's sign-in**: `~/.gitconfig` hands github.com to `gh` (`gh auth setup-git`, run by the owner on 15 Nov 2026), so a plain `git push` works. If one ever fails with "could not read Username", check `gh auth status` first.

Under Cowork only (not Claude Code): its shell can't run git safely on this folder and can't touch `.github/workflows/`, so edit with file tools and hand over the git lines.

**Verify, don't assert.** Read the file, the log, the API. When the owner says something works, believe them and go look. GitHub's tree and contents API have served stale listings here; fetch `raw.githubusercontent.com` instead.
