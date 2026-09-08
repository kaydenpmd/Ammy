# Ammy

Apple Music on iPhone → Discord Rich Presence on a Windows desktop, via a relay
you host yourself.

```
iPhone ──https──▶ Cloudflare Tunnel ──▶ relay.py ──IPC──▶ Discord desktop
```

No user token, no self-botting. Discord has no Rich Presence SDK on iOS, and
setting presence from a phone directly would mean opening a Gateway WebSocket
with a user token — against ToS, and accounts get terminated for it. So the
phone never talks to Discord at all. It POSTs now-playing JSON to a relay on
your PC, and the relay uses the desktop client's local IPC socket, which is the
sanctioned path.

The cost of that design is the first limitation below, and it isn't a bug.

## 1. Discord application

Create one at `discord.com/developers/applications`. You only need its ID.

The application's **name** is the text that appears after "Listening to", so
name it `Apple Music` — it should describe the source, not this bridge.

## 2. Desktop relay (Windows)

```
pip install pypresence
```

Create `bridge/.env` next to `relay.py`:

```
DISCORD_CLIENT_ID=your_application_id
RELAY_SECRET=paste_a_long_random_string
PUBLIC_BASE=https://ammy.yourdomain.com
```

A file rather than environment variables, because variables set in a PowerShell
window vanish with it — and a scheduled task inherits none of them.

```
python bridge\relay.py
```

Then expose it with `cloudflared` and your own domain:

```
cloudflared tunnel create ammy
cloudflared tunnel route dns ammy ammy.yourdomain.com
cloudflared tunnel run --url http://localhost:8787 ammy
```

The relay binds to `127.0.0.1` on purpose — the tunnel is the only way in, so
there's no port forwarding and nothing exposed on your LAN. The shared secret is
checked on every request.

`PUBLIC_BASE` is required for artwork on tracks that aren't in Apple's catalog:
the phone uploads the cover and Discord's CDN fetches it back from the relay, so
the relay has to know its own public URL.

### Autostart

`bridge/install-task.ps1` registers a logon Scheduled Task. It must run in the
interactive session, not as a Windows service — Discord's IPC pipe belongs to
the logged-in session, and a session 0 task will start cleanly, listen on 8787,
and never reach Discord.

### Checking which relay is running

```
python bridge\relay.py --version
python bridge\relay.py --summary     # phone check-in gaps over time
curl https://ammy.yourdomain.com/version
```

## 3. Build the IPA without a Mac

Push to `main` and the **Build unsigned IPA** workflow runs: a macOS runner
generates the Xcode project from `project.yml` via XcodeGen, compiles with
signing disabled, and uploads `Ammy-<version>-b<run>-<sha>.ipa` as an artifact.

Signing is skipped because the sideloader re-signs with your Apple ID at install
time. That also means no certificates in CI secrets.

macOS runner minutes bill at 10× on private repos. A public repo is free.

## 4. Install

Download the artifact, unzip, and sideload with **SideStore**. A free Apple ID
means re-signing every 7 days, which SideStore does on-device.

AltStore also works in principle, but AltServer requires iTunes *and* iCloud
direct from Apple; if you have the Microsoft Store versions installed, you'll
hit "The provided anisette data is invalid" and there is no clean way back.

## 5. Run it

Enter `https://ammy.yourdomain.com/now-playing` and your shared secret, tap
Start, grant media library access, and allow notifications when asked.

The **Version** row on that screen shows `1.0 (7)` — the build number matches
the artifact name, so you can always tell which build is on the phone.

### Shortcuts

```
ammy://music        start, then reopen Apple Music
ammy://background   start, then drop to the Home Screen
```

Worth wiring `ammy://music` to a Shortcuts automation on **Music is opened**.
Nothing restarts Ammy after a reboot or a force quit, and that automation closes
the gap.

## Limits worth knowing

- **PC must be awake with Discord desktop open.** The real cost of avoiding
  self-botting. Presence clears after 90s of silence rather than leaving a stale
  song up.
- **Apple Music only.** `MPMusicPlayerController.systemMusicPlayer` sees the
  built-in Music app and nothing else. System-wide now-playing lives behind the
  private MediaRemote framework, which is entitlement-gated.
- **Sideloading is permanent.** The silent-audio keepalive and the private
  `suspend` selector are both App Review violations. This can never ship on the
  App Store, and that's a deliberate trade, not an oversight.
- **Background survival is best-effort.** The silent audio holds the app alive
  only while its audio session is active, and `KeepAlive` restarts it after
  interruptions. It still dies on force quit. `SilenceWatchdog` notifies you 15
  minutes after check-ins stop, which survives force quit, eviction and reboot
  because the notification is already queued with iOS.
- **Cloud tracks are inconsistent.** `nowPlayingItem` is reliable for library
  content and usually fine for streamed catalog tracks, but does return nil
  sometimes. The 5s poll covers missed notifications, not nil.
- **Artwork needs a catalog match or an upload.** Exact lookup by
  `playbackStoreID` first, then a cover uploaded by the phone, then fuzzy iTunes
  search. Plenty of independent releases aren't in the iTunes Store search
  index at all, which is why the first two paths exist.

## Files

```
project.yml                     XcodeGen spec — no .xcodeproj is committed
.github/workflows/build-ipa.yml CI producing the unsigned, versioned IPA
bridge/relay.py                 Desktop relay + Discord IPC client
bridge/ipc_test.py              Minimal pypresence test, no HTTP layer
Ammy/
  AmmyApp.swift                 SwiftUI entry point and settings screen
  PresenceController.swift      Wires playback changes to relay pushes
  NowPlayingMonitor.swift       MediaPlayer observation, store ID + cover art
  PresenceRelay.swift           HTTPS client for the relay
  KeepAlive.swift               Silent audio to survive backgrounding
  SilenceWatchdog.swift         Notification for when the app isn't running
```

`CLAUDE.md` carries the design decisions and the traps already paid for. Read it
before changing anything non-obvious.
