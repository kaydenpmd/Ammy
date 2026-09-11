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
iPhone ──https──▶ <machine>.<tailnet>.ts.net (Tailscale Funnel) ──▶ relay.py ──IPC──▶ Discord desktop
```

Working as of September 2026. Don't redesign it — the shape is deliberate.

## Why it's built this way

Discord has **no Rich Presence SDK on iOS**. The official path is a local IPC
socket (`\\.\pipe\discord-ipc-0`) that only the desktop client exposes. Setting
presence from a phone directly would mean opening a Gateway WebSocket with a
user token — self-botting, against ToS, accounts get terminated.

The relay exists to avoid that. The phone never talks to Discord; it POSTs
now-playing JSON to a relay on the PC, and the relay uses the sanctioned IPC
path. **Any change that moves Discord communication onto the phone is wrong.**

Cost of this design: presence requires the PC awake with Discord desktop open.
That's accepted, not a bug to fix.

## Layout

```
project.yml                     XcodeGen spec — no .xcodeproj is committed
.github/workflows/build-ipa.yml CI producing an unsigned, versioned IPA
bridge/relay.py                 Desktop relay + Discord IPC client
bridge/install-task.ps1         Registers the logon Scheduled Task
bridge/ipc_test.py              Minimal pypresence test, no HTTP layer
Ammy/
  AmmyApp.swift                 SwiftUI entry point + settings screen
  PresenceController.swift      Wires playback changes to relay pushes
  NowPlayingMonitor.swift       MediaPlayer observation; store ID + cover art
  PresenceRelay.swift           HTTPS client for the relay
  KeepAlive.swift               Silent audio to survive backgrounding
  Diagnostics.swift             The phone's self-report, sent with every push
  SilenceWatchdog.swift         Notification for when the app isn't running
```

**The running relay is not in the repo tree.** On the main PC the live copy is
a loose file at `C:\Users\links\Python Scripts\relay.py`, with `.env`,
`art_cache\`, `relay.log`, `ammy-uptime.log` and `install-task.ps1` beside it.
Both `_load_env_file()` and `ART_DIR` resolve relative to that folder, so a
`.env` in the repo's `bridge/` would never be read. Edit the running copy, then
sync `bridge/relay.py` to match — they have silently diverged before.

## Telling builds apart

Both halves are versioned. Check these before debugging anything.

**Relay** — `RELAY_VERSION` near the top of `relay.py`, with a changelog in the
comment above it. Readable three ways without the filename ever changing:

```
[init] relay <version>      relay.log, every startup
GET /version                e.g. https://kaydenspc.<tailnet>.ts.net/version
python relay.py --version
```

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
build number is the CI run, and the artifact is named to match:
`Ammy-1.0-b7-a1b2c3d.ipa`. Matching numbers means the phone is running the
build you think it is. `MARKETING_VERSION` in `project.yml` is the only version
number a human sets; the build number climbs on its own.

Older notes told you to grep `relay.py` for the string `artwork_by_store_id` to
guess whether it was current. That hack is retired — use the version.

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

Related, and separate: elements *melting into each other* is a different effect
that does need a `GlassEffectContainer` and more than one glass element. A lone
button has nothing to merge with. Conflating the two is what sent this the wrong
way — they are unrelated limitations.

**Silent failure is this project's recurring bug.** Three separate times, a
function returned `None` on a failure path without logging, and the empty log
read as "working" rather than "broken." Every artwork path now prints on
failure. **When adding a new failure path, log it** — an unexplained silence
costs days here.

**pypresence enums, not ints.** `update()` calls `.value` on `activity_type`
and `status_display_type`. Passing `2` raises `AttributeError: 'int' object has
no attribute 'value'`, which the worker's generic handler misreads as a dropped
socket, producing an infinite connect/fail/reconnect loop. Use
`ActivityType.LISTENING` and `StatusDisplayType.*`. `push_with_fallback()`
exists to shed unsupported kwargs rather than tearing down the connection.

**A rejected payload is not a dead socket.** This has now bitten twice, from
two different triggers, and the second cost an hour of confusion.

Discord requires `details` and `state` to be at least two characters and
refuses the entire activity otherwise. One-character titles are not exotic —
the track that exposed this was **"i" by Kendrick Lamar**, hit by shuffling.
The refusal arrives as a `ServerError`,
the worker's catch-all read it as a lost connection, closed the socket,
reconnected, re-sent the identical payload, and looped. Presence stayed empty
for about a minute until the song changed and broke the cycle.

Diagnosing it was harder than it should have been because `print(f"[rpc] ...")`
runs *after* a successful push, so the one track responsible is the only one
that leaves no line in the log.

Fixed three ways in 1.3.0: `pad_for_discord()` pads short fields with U+2060,
`PAYLOAD_REJECTED` exceptions are caught separately and the track skipped
rather than the connection torn down, and the reconnect path sleeps so it
cannot spin. **Don't collapse those two `except` clauses back together.**

**`push_with_fallback` matches quoted field names.** It identifies which field
to drop from `'x'` in "unexpected keyword argument 'x'". A bare substring test
is wrong: `state` is a substring of `state_url`, so an error about `state_url`
would shed the *artist line* and leave the real offender in place. Don't
"simplify" that back.

**currentPlaybackTime is unreliable right after a track change.** It can report
the previous song's position for a second or two. `PresenceController` re-reads
elapsed at send time (not from the Combine-captured snapshot) and fires a
correction push 2.5s after every change. Removing that correction reintroduces
wrong progress bars on skip.

**The playhead anchor is paired with the push's arrival time, never with
`time.time()`.** This is the single most expensive bug the project has had, and
it is invisible on inspection because every individual calculation looks right.

`build_payload()` runs once per second in the RPC worker. The phone refreshes
`elapsed` once every thirty. So for thirty consecutive calls the same frozen
reading is in hand — and computing `start = time.time() - elapsed` against it
slides the anchor forward one second per second. Discord's bar falls steadily
behind for thirty seconds, then snaps forward when the next push lands. That
was the rubberbanding.

`Playhead.anchor()` takes an `observed_at` argument for exactly this reason,
and `build_payload()` receives it from `state.get()`. Never pass either one
`time.time()`.

Diagnosis tip: the giveaway was `[playhead] re-anchored +10.0s` repeating with
*identical* drift. A noisy sensor gives varying numbers; a constant drift is a
clock, not a measurement.

`_materially_different()` still applies a 2-second tolerance to `start`/`end`,
which is now belt-and-braces rather than load-bearing — a correct anchor
doesn't move between pushes at all.

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

**Don't transcribe config from screenshots.** `DISCORD_CLIENT_ID` was once
copied from a screenshot with one digit misread, and Discord answered
`Error Code: 4000 Message: Client ID is Invalid` — which reads like a deleted
application, not a typo. Have PowerShell write the file from the live variables
instead, and print `.Length` rather than the value when checking secrets.

## Diagnostics

**The app cannot report its own death.** By the time anyone notices it is gone
there is nothing left running to ask, and the relay only ever sees that pushes
stopped — never why. So every push carries a `diag` snapshot of the phone's
condition, the relay keeps the most recent one, and `note_silence()` prints it
onto the "phone stopped checking in" line. That last snapshot is the entire
account of what preceded a silence.

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
- `mem` is `phys_footprint`, the number jetsam actually measures — not
  `resident_size`, which reads high and matches nothing. Observed 16–25MB.
- `thermal` was added on spec with no theory behind it and immediately became
  the most interesting unexplained signal: it flaps to `serious` repeatedly.
  When you are debugging blind, record everything cheap; you cannot correlate a
  signal you did not keep.

`[keepalive]` lines in `relay.log` record changes as they happen, so the log
shows the *sequence* leading to a death rather than only the state at the end of
it. `GET /diag` returns the latest snapshot on demand, authenticated.

### Was it killed, or just unreachable?

Two different bugs with two different fixes, and until relay 1.8.0 the log could
not tell them apart. A push that fails never arrives, so from the relay's side
"iOS evicted the app" and "the app was alive and could not reach me" are the
same observation: silence. The evidence has to survive the outage and come back
with the first push that gets through.

Two fields carry it, from opposite directions:

- `app_uptime_s` resets when the process does. The relay keeps the value from
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

## Artwork

Resolution order, best first:

1. **Catalog ID from the phone** (`store_id` ← `playbackStoreID`) — exact
   lookup, no guessing. This is the normal path.
2. **JPEG uploaded by the phone** (`artwork_b64`) — exact, for tracks with no
   catalog ID. Requires `PUBLIC_BASE`; the relay caches it under a hash of the
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

**The phone sends the JPEG once per track, not per heartbeat** — it's ~80 KB
and the heartbeat is every 30s. `existing_uploaded_artwork()` reuses the file
already on disk, without which the cover would appear on the first push and
vanish on the next.

**A `weak match` line now means the phone didn't send a store ID** for that
track. With the ID present the fuzzy path never runs, so those lines have
become a signal about the iOS side rather than about Apple's search index.

`ART_MIN_SCORE` defaults to **0.35**, not the 0.55 an earlier version of this
document claimed.

## Clickable presence

Discord supports hyperlinking activity text and artwork, and pypresence 4.6.2
accepts all of it:

| Field | Opens from | Source |
|---|---|---|
| `details_url` | the title line | `trackViewUrl` |
| `state_url` | the artist line | `artistViewUrl` |
| `large_url` | the cover art | `collectionViewUrl`, with `?i=` stripped |

`collectionViewUrl` arrives carrying `?i=<trackId>`, which opens the album with
the current song selected — the same destination `details_url` already provides.
`_album_url()` drops that one parameter and leaves the rest of the query alone,
so the two links mean different things: title goes to the song, cover goes to
the album.

All three come out of the same iTunes lookup that fetches artwork, so links
cost no extra requests. They are populated **only from the exact store-ID
lookup, never from fuzzy matching** — a near-miss cover is a cosmetic
annoyance, but a link that opens the wrong song is a broken promise.

Album name is `large_text`, which Discord renders as *both* the cover tooltip
and a visible third line on the card — one field, two places, and they can't be
separated. It's off by default behind `SHOW_ALBUM`. Spotify's presence shows a
tooltip with no third line, but that's a first-party card Discord special-cases
(it also carries a "Play on Spotify" button); third-party RPC gets the generic
renderer and doesn't get to choose.

## Build and deploy

Push to `main` triggers `.github/workflows/build-ipa.yml` on a `macos-26`
runner. It reads `MARKETING_VERSION` out of `project.yml`, passes
`CURRENT_PROJECT_VERSION=${{ github.run_number }}`, builds unsigned
(SideStore re-signs at install), and uploads `Ammy-<version>-b<run>-<sha>`.

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
and refreshes on-device, so it doesn't hit that wall. Don't suggest AltStore.

## Autostart

Installed on the main PC as the logon Scheduled Task **`Ammy Relay`**, via
`install-task.ps1` beside the running `relay.py`: `pythonw.exe relay.py`, 30s
delay, `-LogonType Interactive`, `-RunLevel Limited`.

Interactive is load-bearing. "Run whether user is logged on or not" registers a
session 0 task that starts cleanly, listens on 8787, and never reaches
Discord's IPC pipe — a failure that looks like a Discord problem, not a task
problem.

```powershell
Start-ScheduledTask -TaskName "Ammy Relay"
Stop-ScheduledTask  -TaskName "Ammy Relay"
Get-ScheduledTaskInfo -TaskName "Ammy Relay" | Select LastRunTime,LastTaskResult
```

`LastTaskResult` `267009` means running. `Get-Process pythonw` is an unreliable
check — `relay.log` is the real evidence. `pythonw.exe` resolves to the
WindowsApps app-execution alias, a zero-byte reparse point; this was expected to
break under Task Scheduler and **does not**. Don't spend time rewiring it.

The task inherits no variables from any PowerShell window, which is why `.env`
is mandatory rather than convenient.

## Runtime config

`_load_env_file()` reads `.env` **from the folder containing `relay.py`** and
returns silently if absent. Real environment variables still win — and one set
in a PowerShell window applies only to a relay launched from that window, which
is why a value can look set in one shell and be empty to the running process.

- `DISCORD_CLIENT_ID` — the Discord application ID. Its **name** is the text
  after "Listening to", so the application stays named `Apple Music`, not Ammy:
  that string should describe the source, not the bridge.
- `RELAY_KEY` — the shared key; must match the app's **Key** field.
  `RELAY_SECRET` is the old name and is still read, so an existing `.env`
  keeps working. Headers follow the same rule: `X-Relay-Key` is current,
  `X-Relay-Secret` is still accepted, so an older build of the app keeps
  working against an updated relay.
- `PUBLIC_BASE` — e.g. `https://kaydenspc.<tailnet>.ts.net`. **Required** for
  uploaded artwork: Discord's CDN fetches the image itself and can't reach
  127.0.0.1.
- `PUBLIC_READ` — `1` serves `GET /now-playing` with no key and with CORS, so
  a web page can read the feed directly. Off by default, and a separate switch
  on purpose: it publishes what you are listening to at a URL anyone holding
  the link can poll. A key cannot be the answer there, because a public page
  would have to embed it.
- `STATUS_LINE` — `name` / `state` / `details`, the compact member-list line.
  Defaults to `state` (artist).
- `SHOW_ALBUM` — `1` restores the album name. Default off; see above.
- `RELAY_PORT` — defaults to 8787.
- `ART_MIN_SCORE` — fuzzy floor, default 0.35. `0` always takes the best match.
- `ART_DIR` — uploaded-art cache, default `art_cache`.
- `UPTIME_LOG` — phone check-in gaps, default `ammy-uptime.log`.
  `python relay.py --summary` reads it back.

Under `pythonw.exe` there is no console and `sys.stdout` is None, so `relay.py`
redirects output to `relay.log` in the same folder. That file is the primary
diagnostic.

Relay binds `127.0.0.1` only; the tunnel is the sole ingress. `/art/` is
deliberately unauthenticated — Discord's CDN can't send the secret header, and
filenames are hashes, so they aren't enumerable.

Gap logging exists to answer whether iOS actually kills the app in the
background. Gaps are classified as phone-silent versus relay-was-down so a PC
reboot isn't miscounted as the app dying.

Two halves record it, and both are needed. `note_checkin()` writes the gap when
a push *arrives*, so it can only measure a silence that ended — a death you
never noticed would never have been written down at all. `note_silence()` is
the other half: the RPC worker watches the clock and logs the moment check-ins
stop. It works whether or not music was playing, because `updated_at` is
stamped on every push including `playing: false` ones — a paused app keeps
checking in, a dead one doesn't. `python relay.py --summary` reports silences
that never got a matching return as "app died and stayed dead".

On the phone, `SilenceWatchdog` is the third leg: it tells you *that* it died,
15 minutes after the fact. The relay logs tell you how long.

Each entry is stamped `[relay <version> / app <build>]`, the app build coming
from `app_version` on every push. **Don't split the log into per-version
files.** Whether the phone survives backgrounding is decided by the iOS build,
not the relay's, and the relay restarts far more often than the app changes —
splitting would fragment the data by the wrong variable and can't be undone.
A stamped line can be grouped any way you like later, which is what
`--summary` does. Entries predating the stamping group as "before builds were
recorded", so the pre-KeepAlive era stays visible as history without skewing
current numbers — no archiving needed.

## Where things stand (September 2026)

Working and verified: autostart, artwork via store ID, clickable title/artist/
cover, album line removed, versioning on both halves, both secrets rotated, and
the progress bar.

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
the app. Since the `KeepAlive` fix, every recorded gap has had a mundane
explanation and none has been an iOS reclaim.

**Verified — the app survives the night.** Roughly eight unbroken hours on
Sept 2 with no gap logged, the first clean night on record. Compare the 39-hour
silent death of Aug 27–29 that prompted the `KeepAlive` interruption fix. One
night is not proof; check `--summary` periodically and watch whether
"never came back" ever appears.

Lifetime figures in `--summary` still include pre-fix history — the 39-hour
death dominates "longest" and "total silent time" and will for a long while.

**Done — secrets rotated (Sept 2 2026).** `RELAY_SECRET` regenerated locally by
PowerShell straight into `.env` so the value never appeared in a chat or a
screenshot, then entered into the app. Tunnel token refreshed in the dashboard
and the cloudflared service reinstalled — the refresh alone does *not* close
existing connections, so the reinstall is what actually retires the old token.
Verified end to end with `https://ammy.kaydenpmd.net/version`.

**Done — the laptop connector is gone.** The tunnel now lists one connector,
`KaydensPC`. Nothing to clean up.

**Done — the `ammy://` URL scheme is gone (11 Sept 2026).** `ammy://music` and
`ammy://background` are removed, along with `BounceTarget`, `onOpenURL`,
`performBounce`, the private `suspend` selector, `CFBundleURLTypes`,
`LSApplicationQueriesSchemes`, and the settings section that advertised them.

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

`cloudflared` still works and the relay is indifferent to what fronts it, so
this is a change of default, not a removal.

**Done — playhead fixed (Sept 2 2026).** Cause was the arrival-time bug above,
not staleness in `currentPlaybackTime` as long assumed. After the fix: zero
`[playhead]` log lines, and 19 pushes across 15 tracks where a single track
used to generate thirty-odd — heartbeats now produce identical payloads and get
suppressed.

The `Playhead` class also carries seek detection and a rule that prefers any
reading implying the song is further along, on the theory that a stale read can
only ever make it look earlier. In practice **no staleness has been observed at
all**, so that rule has never fired. It is insurance, not a working mechanism;
don't cite it as evidence that staleness exists.

Should either secret need rotating again: the tunnel token lives in the
cloudflared Windows service's registry `ImagePath`, not in a `config.yml` —
token-based installs have no config file. In the dashboard the **Refresh
token** button is at the bottom of the **Add a connector** panel, which the
Cloudflare docs still call "Add a replica".

**Untested — the uploaded-JPEG path.** `art_cache\` is still empty because
every track played so far has been in the catalog. It's a genuine fallback now
rather than the only hope, but it has never actually run.

**Done — the rename shipped (8 Sept 2026).** Committed, pushed, and installed as
build 25. See the top of this file.

**Done — KeepAlive rewritten and instrumented (8 Sept 2026).** Configuration
changes observed, `.began` counted separately from `.ended`, resume failures
retried rather than swallowed, `engine.isRunning` re-checked every 10s and again
on every push. The relay learned to record the `diag` payload and stamp it onto
death lines.

**The September regression, and what it actually was.** From 4 Sept the app began
dying every 7–63 minutes during waking hours; before that, windows ran 8–87
hours. The break dates precisely to a phone reboot at 13:03–13:19 on 4 Sept, and
the relay ran unrestarted across it, so the change was entirely phone-side. The
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
retried and recovered. Do not remove the retry loop or the periodic
`engine.isRunning` check — this line is what they are for.

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

Moved here from `AMMY-HANDOFF.md` on 9 Sept 2026, which was then deleted.

**1. Shippable to others**, in the order things actually block:

- **The relay is a dead end on first run** — it exits with "Set RELAY_KEY",
  which a new user cannot act on. It should generate its own key, write its
  own `.env`, and show it (a QR the app scans would remove the typing entirely).
- **"Endpoint Unreachable" means two different things** — a dead receiver and a
  wrong key produce the same message. The app already knows the difference between a
  connection failure and a 401. Small fix; would otherwise be most of the support
  load. Partly addressed: `http://` now has its own message, because iOS blocks
  plain HTTP at the network layer and that failure was indistinguishable from an
  unreachable receiver.
- **Autostart is Windows-only.**
- **Each user needs their own Discord application**, which is a five-step detour
  of its own. Note the application's *name* is the "Listening to" text, so it
  stays `Apple Music` — that string describes the source, not the bridge. Fine
  for one person; think hard before it is on hundreds of profiles.
- Counted end to end, a stranger now needs three accounts — Discord, Tailscale,
  Apple — and about eight steps. The single biggest lever left is packaging the
  relay as one self-provisioning executable that registers its own autostart —
  that collapses Python, the relay, the key and autostart into one download.

**2. Shortcuts relaunch automations.** Built 9 Sept, then deleted to get a clean
stability measurement. Worth rebuilding only if the app still dies. The recipe,
so it is not re-derived:

- One shortcut holds the logic and the secret: `GET /status` with an
  `X-Relay-Key` header → `If` contents **contains** `stale` → `If Is Locked`
  (do nothing; an app cannot be launched from the lock screen) → `Otherwise`
  `Open App [Ammy]` then `Open App [Current App]`.
- `Get Current App` must run **first**, before anything else — once Ammy is
  foregrounded, "current app" is Ammy.
- Use `Open App`. There is no alternative any more — the `ammy://` scheme was
  removed on 11 Sept 2026, partly because it made Ammy navigate away itself and
  race the return. Launching the app directly needs no delay at all.
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
rather than being live. It fits the modular shape though: same relay, two
senders, one live and one effortless.

**5. tvOS** was investigated. `MPMusicPlayerController`, `systemMusicPlayer` and
`nowPlayingItem` are all available on tvOS 14+, so the reading side ports.
Unknown: whether the silent-audio keepalive survives tvOS backgrounding. Cheap
to test with a stub target before committing to it.

## Working with the owner

Limited coding experience — comfortable running commands and reading output,
not writing code. Prefers concise, concrete instructions over conceptual
explanation. Give **one command at a time** and wait for output; stacked
commands hide failures when an early one hangs.

The repo is cloned at `C:\Users\links\Repos\Ammy` (renamed from
`repos\ampresence` on 9 Sept 2026). Edit the files in place; there is no need to
hand over whole files for web upload, which is what this document said from
before the clone existed.

**Git commands are the owner's to run, and this is not a preference.** Under
local Cowork the shell is a separate Linux VM whose mount of host folders does
not permit unlink — `git rm`, `git reset --hard`, even `git status` fail partway
and leave a stale `.git/index.lock` blocking the owner's next command. Under
cloud Cowork there is no shell on the machine at all; files are reached through
the desktop app, and `.github/workflows/` is refused outright as a protected
path. Either way: edit with the file tools, hand over the git lines.

Most "what state is this in?" questions can be answered without running
anything. `.git/logs/HEAD` is the reflog, `.git/logs/refs/remotes/origin/main`
records pushes, and `.git/config` holds the remote URL. Reading those three
settled "is the rename committed?" in one call on 8 Sept, against a handoff note
that claimed otherwise.

**Verify, don't assert.** This project has burned several rounds on confident
wrong answers — that Discord couldn't hyperlink activity text (it can:
`details_url`, `state_url`, `large_url`), that a bug was in one place when the
logs hadn't been read yet. Read the file, read the log, check the API. When the
owner says something works, believe them and go look. Also: GitHub's tree and
contents API endpoints have served **stale cached listings** here, showing a
week-old file set as current — fetch `raw.githubusercontent.com` directly
instead of trusting a listing.
