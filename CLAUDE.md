# Context for Claude Code

Everything is called **Ammy** — Home Screen name, Xcode target, scheme, source
folder, and bundle ID `com.local.ammy`. This used to be `AMPresence` /
`com.local.ampresence`.

**The rename is not finished.** It exists in the working tree only: as of 8 Sept
2026 it is uncommitted, unpushed, unbuilt and uninstalled. Check `git log`
before believing otherwise — this paragraph was originally written in the past
tense, describing an outcome that had not happened, and the next session caught
the contradiction rather than the docs catching it.

Changing the bundle ID makes iOS treat the next build as a **new app** rather
than an upgrade, so installing it will cost one re-pairing: delete the old Ammy
from the phone first (otherwise both copies run and both push to the relay),
then re-enter the endpoint and secret and re-grant media-library and
notification permissions.

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
bridge/ipc_test.py              Minimal pypresence test, no HTTP layer
Ammy/
  AmmyApp.swift                 SwiftUI entry point + settings screen
  PresenceController.swift      Wires playback changes to relay pushes
  NowPlayingMonitor.swift       MediaPlayer observation; store ID + cover art
  PresenceRelay.swift           HTTPS client for the relay
  KeepAlive.swift               Silent audio to survive backgrounding
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

**KeepAlive must survive interruptions.** The silent audio holds the app alive
only while its `AVAudioSession` is active. A call, alarm or Siri invocation
stops the engine, and nothing restarts it on its own — the app then has no
audio justifying its background time and iOS reclaims it minutes or hours
later. `KeepAlive` observes `interruptionNotification` and
`mediaServicesWereResetNotification` and rebuilds. Before that fix, the app
died silently for 39 hours straight (Aug 27–29).

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
| `large_url` | the cover art | `collectionViewUrl` |

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

## Working with the owner

Limited coding experience — comfortable running commands and reading output,
not writing code. Prefers concise, concrete instructions over conceptual
explanation. Give **one command at a time** and wait for output; stacked
commands hide failures when an early one hangs.

The repo is cloned at `C:\Users\links\repos\ampresence`. Edit the files in
place; there is no need to hand over whole files for web upload, which is what
this document used to say from before the clone existed.

**Git commands are the owner's to run, and this is not a preference.** Under
local Cowork the shell is a separate Linux VM, and its mount of host folders
does not permit unlink — so `git rm`, `git reset --hard`, and even `git status`
fail partway and leave a stale `.git/index.lock` that blocks the owner's next
command. Edit with the file tools, hand over the git lines.

**Verify, don't assert.** This project has burned several rounds on confident
wrong answers — that Discord couldn't hyperlink activity text (it can:
`details_url`, `state_url`, `large_url`), that a bug was in one place when the
logs hadn't been read yet. Read the file, read the log, check the API. When the
owner says something works, believe them and go look. Also: GitHub's tree and
contents API endpoints have served **stale cached listings** here, showing a
week-old file set as current — fetch `raw.githubusercontent.com` directly
instead of trusting a listing.
