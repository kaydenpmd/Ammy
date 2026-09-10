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
iPhone ──https──▶ ammy.kaydenpmd.net (Cloudflare Tunnel) ──▶ relay.py ──IPC──▶ Discord desktop
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
GET /version                e.g. https://ammy.kaydenpmd.net/version
python relay.py --version
```

This document deliberately does **not** state the current version — it went
stale within the hour, twice. Ask `/version` instead.

`/health` still returns exactly `ok` and nothing else — Shortcuts test for that
string, which is why the version got its own route.

**iOS app** — the Status section shows a **Version** row, e.g. `1.0 (7)`. The
build number is the CI run, and the artifact is named to match:
`Ammy-1.0-b7-a1b2c3d.ipa`. Matching numbers means the phone is running the
build you think it is. `MARKETING_VERSION` in `project.yml` is the only version
number a human sets; the build number climbs on its own.

Older notes told you to grep `relay.py` for the string `artwork_by_store_id` to
guess whether it was current. That hack is retired — use the version.

## Gotchas already paid for — don't rediscover these

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
- `RELAY_SECRET` — shared secret; must match the app's Secret field.
- `PUBLIC_BASE` — e.g. `https://ammy.kaydenpmd.net`. **Required** for uploaded
  artwork: Discord's CDN fetches the image itself and can't reach 127.0.0.1.
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

**Under test — stability.** Stress-test window opened 9 Sept 11:28 CDT with all
Shortcuts relaunch automations deleted, so every alive window from then on is the
app's own unaided lifetime and `appup` on a death line reads as that lifetime
directly. First data point: one continuous run of 8h34m through a normal
morning, against a 7–63 minute baseline. One run is not a result; check
`--summary` grouped by build before concluding anything.

## Open work

Moved here from `AMMY-HANDOFF.md` on 9 Sept 2026, which was then deleted.

**1. Shippable to others**, in the order things actually block:

- **The tunnel is the wall.** A stranger needs a domain and a Cloudflare account
  before anything else works. Tailscale is the likely answer. Cloudflare quick
  tunnels avoid the domain but hand out a new hostname each restart, which breaks
  the endpoint saved in the app.
- **The relay is a dead end on first run** — it exits with "Set RELAY_SECRET",
  which a new user cannot act on. It should generate its own secret, write its
  own `.env`, and show it (a QR the app scans would remove the typing entirely).
- **"Relay unreachable" means two different things** — a dead relay and a wrong
  secret produce the same message. The app already knows the difference between a
  connection failure and a 401. Small fix; would otherwise be most of the support
  load.
- **Autostart is Windows-only.**
- **Each user needs their own Discord application**, which is a five-step detour
  of its own. Note the application's *name* is the "Listening to" text, so it
  stays `Apple Music` — that string describes the source, not the bridge. Fine
  for one person; think hard before it is on hundreds of profiles.
- Counted end to end, a stranger currently needs four accounts and about ten
  steps. The single biggest lever is packaging the relay as one self-provisioning
  executable that registers its own autostart — that collapses Python, the relay,
  the secret and autostart into one download.

**2. Shortcuts relaunch automations.** Built 9 Sept, then deleted to get a clean
stability measurement. Worth rebuilding only if the app still dies. The recipe,
so it is not re-derived:

- One shortcut holds the logic and the secret: `GET /status` with an
  `X-Relay-Secret` header → `If` contents **contains** `stale` → `If Is Locked`
  (do nothing; an app cannot be launched from the lock screen) → `Otherwise`
  `Open App [Ammy]` then `Open App [Current App]`.
- `Get Current App` must run **first**, before anything else — once Ammy is
  foregrounded, "current app" is Ammy.
- Use `Open App`, not `Open URLs ammy://...`. The URL scheme makes Ammy navigate
  to the Home Screen itself, which races the return. Launching the app directly
  needs no delay at all.
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

What was considered and why it lost:

- **App Store: structurally impossible.** The silent-audio keepalive and the
  private `suspend` selector are both straight rejections, and no legitimate
  background mode delivers 30-second updates — `audio` demands real audio,
  `fetch` and `processing` are opportunistic and measured in hours. There is no
  version of this app, as designed, that passes review.
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
