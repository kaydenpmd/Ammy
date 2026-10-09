# Ammy

Ammy reads what's playing in Apple Music on your iPhone and POSTs it as JSON to
an HTTPS endpoint you choose, on every track change and every 30 seconds while
it runs. It is built to pair with [Issun](https://github.com/kaydenpmd/Issun), a
Windows app that turns those pushes into Discord Rich Presence, and it works
with anything else that accepts an HTTPS POST.

This README sets up that pairing:

```
iPhone ──https──▶ Tailscale Funnel ──▶ Issun ──IPC──▶ Discord desktop
```

No user token, no self-botting. Discord has no Rich Presence SDK on iOS, and
setting presence from a phone directly would mean opening a Gateway WebSocket
with a user token — against ToS, and accounts get terminated for it. So the
phone never talks to Discord at all. Ammy POSTs to Issun on your PC, and Issun
uses the Discord desktop app's local IPC socket, which is the sanctioned path.

The cost of that design is the first limitation below, and it isn't a bug.

## Before you start

- A Windows 10 or 11 PC, 64-bit, that stays awake, with the Discord desktop app
  open and signed in on the same Windows account. Discord in a browser can't
  show presence from other apps.
- A free **Tailscale** account. No domain, no DNS records, no port forwarding,
  and nothing exposed on your LAN.
- A **Discord** account, to create the application whose name becomes the
  "Listening to" text.
- An iPhone on iOS 26 or later, and an **Apple ID** for sideloading. A free one
  re-signs every 7 days.

## 1. Discord application

Create one at `discord.com/developers/applications`. You only need its
**Application ID**, which goes into Issun in the next step.

The application's **name** is the text that appears after "Listening to", so
name it `Apple Music` — it should describe the source, not the apps carrying it.

## 2. Issun (Windows)

Issun is the receiver: one `.exe` with a window and a tray icon, and nothing to
install alongside it. Download it from
[Issun's Releases page](https://github.com/kaydenpmd/Issun/releases) and follow
the Setup steps in [its README](https://github.com/kaydenpmd/Issun#setup), which
keep up with Issun in a way a copy here wouldn't. The parts that matter to Ammy:

- On first run Issun generates its **key**. It goes into Ammy in step 6.
- Paste the Discord Application ID into **Settings → Discord application ID**.
  Paste rather than retype it: one wrong digit gets "Client ID is Invalid",
  which reads like a deleted application rather than a typo.
- Issun listens on `127.0.0.1` only, on port 8787 unless you change it in
  Settings, so nothing reaches it except through Funnel. It learns its public
  address from Tailscale, which is what a cover uploaded by the phone needs:
  Discord's CDN fetches the image back from your PC.

If you ran the Python `relay.py` that used to live in this repo, Issun's
**Settings → Import relay .env…** brings its key across, so Ammy needs no
changes.

## 3. Expose it with Tailscale Funnel

Install Tailscale on the PC from `tailscale.com/download` and sign in. Then
click **Turn on Funnel** in Issun's **Tailscale** row, which runs:

```
tailscale funnel --bg --https=443 localhost:8787
```

Running it yourself does the same. If the output includes a
`login.tailscale.com` link, open it to allow Funnel on your tailnet, then try
again. Otherwise it prints your public URL:

```
https://your-pc.your-tailnet.ts.net
```

`--bg` is what makes it persist: the setting survives a reboot or a Tailscale
restart, where without it Funnel stops when the terminal that started it
closes. Issun's Tailscale row warns you if it finds Funnel running that way.

```
tailscale funnel status                      # what's currently served
tailscale funnel --https=443 off             # stop serving
```

Funnel only answers while Tailscale is connected, though, and on Windows that
normally waits for Tailscale's tray app, which Windows starts late in sign-in,
after other startup apps. Turn on Tailscale's **Run unattended** setting and it
connects at boot instead.

Three things have to be true on your tailnet: **MagicDNS** enabled, **HTTPS
certificates** enabled, and the `funnel` node attribute present in the policy
file. The default policy grants it to every member. Tailscale links you
straight to whichever one is missing on first run, and Issun's Tailscale row
says what to do next.

### Pin the machine name

Your URL is `https://<machine>.<tailnet>.ts.net`, and the machine half is
generated from the PC's OS hostname by default — so renaming the PC silently
moves your endpoint and the address saved in the app stops resolving. In the
admin console, open the machine and **turn off "Auto-generate from OS
hostname."** Do it before you type the URL into the phone.

The tailnet half (`tail1a2b3.ts.net`, or a word-pair if you picked one) is fixed
once HTTPS certificates have been issued for it.

Funnel can only listen publicly on 443, 8443 and 10000, and the Endpoint Issun
shows assumes 443, so leave it there. The local port is Issun's **Port**
setting, 8787 by default. Change it and Funnel has to point at the new one,
which **Turn on Funnel** does.

### Autostart

Turn on **Start with Windows** in Issun's Settings. It adds Issun to your
account's Run key, so Windows starts it in the tray whenever you sign in, with
no admin rights needed. Move the `.exe` to a folder you'll keep first: the
entry points at wherever Issun last ran from.

Starting at sign-in is also what lets it reach Discord. Discord's IPC pipe
belongs to the signed-in session, and a program started outside it — a Windows
service, or a task set to run whether you're signed in or not — can listen on
8787 and never reach Discord.

### Checking on it

Issun's window answers most questions. Under **Status**, the **Source** row
says whether Ammy is checking in, **Discord** whether presence is connected,
**Receiver** whether Issun holds its port, and **Tailscale** whether Funnel
reaches it. **Diagnostics** holds the phone's last self-report, kept in memory
from the latest push, and the check-in history, read from `uptime.log`, which
counts every silence and groups the gaps by Ammy build. `uptime.log` and the
full log, `issun.log`, are in `%LOCALAPPDATA%\Issun`, which **Diagnostics →
Open log folder** opens.

From outside the PC:

```
curl https://your-pc.your-tailnet.ts.net/version
curl -H "X-Relay-Key: your_key" https://your-pc.your-tailnet.ts.net/diag
```

`/version` needs no key and answers `issun` followed by its version and build
number. **Run these from somewhere other than the PC**, such as the phone's
browser for `/version`, or check-host.net. The PC's own lookups of its ts.net
name are answered by Tailscale with the tailnet address, so they skip Funnel
and can succeed while it is failing everyone else — and Issun's Tailscale row,
which reads Tailscale's own settings, can say Funnel is on at the same time.

`/diag` returns the phone's most recent self-report: whether the silent-audio
engine is actually running, how often it has been restarted and why, how many
audio route changes and interruptions there have been, memory footprint, and
both app and device uptime.

That report exists because **the app cannot tell you it died.** By the time
anyone notices it is gone there is nothing left running to ask. So the phone
sends its condition with every push, Issun keeps the latest one, and the
"phone stopped checking in" line in `uptime.log` carries it:

```
phone stopped checking in  last seen 17:22:13  last state: engine=no want=yes
route=BluetoothA2DPOutput resumes=3 fails=0 heals=0 cfg=1 routechg=4 int=2/1
mem=38MB avail=1904MB availmin=1880MB memwarn=0 state=background lpm=no
thermal=nominal appup=1840s devup=402118s pushfail=0/0
```

`engine=no want=yes` means the keepalive was already dead before the app was.
A climbing `mem` before a death means iOS reclaimed the app under memory
pressure instead — a different problem, with a different fix.

## 4. Build the IPA without a Mac

Push to `main` and the **Publish to AltStore source** workflow runs. It calls
**Build unsigned IPA and simulator app**, where a macOS runner generates the
Xcode project from `project.yml` via XcodeGen, compiles with signing disabled,
and uploads `Ammy-<version>-b<build>-<sha>.ipa` as an artifact, the build number
being a commit count. The publish job then releases that `.ipa` on GitHub and in
the AltStore source; see `PUBLISHING.md`.

Signing is skipped because the sideloader re-signs with your Apple ID at install
time. That also means no certificates in CI secrets.

macOS runner minutes bill at 10× on private repos. A public repo is free.

## 5. Install

In **SideStore**, add the source `https://apps.kaydenpmd.net/source.json`:
**Browse → Sources** (top right) **→ +**, then paste. Or open
`apps.kaydenpmd.net` on the phone and tap **Add to SideStore**. Ammy installs
from there, and new builds arrive the same way. A free Apple ID means re-signing
every 7 days, which SideStore does on-device.

To install a build by hand instead, download its `.ipa`, from this repo's
Releases page or as the workflow artifact, and add it with SideStore's **+**
under **My Apps**. The artifact upload uses `archive: false`, so what you
download is the `.ipa` itself rather than a zip containing one — an `.ipa` is
already a zip, and wrapping it in another just adds a step.

AltStore also works in principle, but AltServer requires iTunes *and* iCloud
direct from Apple; if you have the Microsoft Store versions installed, you'll
hit "The provided anisette data is invalid" and there is no clean way back.

## 6. Run it

Issun's **Connect a source** section shows the two values Ammy needs. In Ammy's
**Endpoint** section, put Issun's **Endpoint** into **URL** — your Funnel URL
with `/now-playing` on the end — and Issun's **Key** into **Key**:

```
your-pc.your-tailnet.ts.net/now-playing
```

You can leave off `https://` — Ammy asks before adding it, rather than rewriting
what you typed behind your back, and stores the result so it only asks once.
Plain `http://` is refused outright: iOS blocks it at the network layer, and
without the explicit message that failure is indistinguishable from a receiver
that's simply down.

The key is optional to Ammy. It will POST without one, and omits the header
entirely rather than sending an empty one — "no key configured" is a clearer
signal to a receiver than a header with nothing after it. Issun refuses
unauthenticated requests, so you do need one here; a receiver of your own may
not. If you make a **New key…** in Issun, Ammy's pushes are refused, and Ammy
says "Key Rejected", until its Key field has the new one.

Tap Start, grant media library access, and allow notifications when asked. On
the PC, Issun's **Source** row then says Ammy is checking in, and its
**Discord** row says "Connected as" your name.

Notifications are not optional. `UNUserNotificationCenter.add()` succeeds on an
unauthorized center and delivers nothing, so declining leaves the watchdog
silently inert rather than visibly broken.

The **Version** row on that screen shows something like `1.0 (24)` — the build
number matches the artifact name, so you can always tell which build is on the
phone.

### Restarting it automatically

Ammy starts reporting the moment it is launched, however it is launched. So a
Shortcuts automation needs only **Open App → Ammy** — no deep link, no URL
scheme, nothing to configure in the app. Wire that to **Music is opened** and
the gap left by a reboot or a force quit mostly closes itself.

If you want the automation to hand you back to whatever you were doing, put
**Get Current App** first, before anything else in the shortcut. Once Ammy is in
the foreground, "current app" is Ammy.

## Reading the feed yourself

Discord doesn't have to be the only consumer. Issun serves the same path in
both directions — the phone POSTs to `/now-playing`, and anything else can GET
it:

```
curl -H "X-Relay-Key: your_key" https://your-pc.your-tailnet.ts.net/now-playing
```

```json
{
  "playing": true,
  "stale": false,
  "updated_ago": 4.2,
  "title": "…", "artist": "…", "album": "…",
  "duration": 214.0, "elapsed": 61.3,
  "artwork": "https://…",
  "links": {
    "song": "https://music.apple.com/…",
    "artist": "https://music.apple.com/…",
    "album": "https://music.apple.com/…"
  },
  "explicit": true
}
```

When nothing is playing, or Ammy has been quiet for more than 90 seconds, only
`playing`, `stale` and `updated_ago` appear. `explicit` appears only when it's
true.

It's a projection, not the raw push — the ~80KB of base64 artwork and the whole
diagnostics block are deliberately left out, and a GET never triggers an
outbound iTunes lookup, so nobody can use the endpoint to make your machine
issue traffic. Artwork and links come from cache or are omitted.

Turn on **Public now playing** in Issun's Settings to serve this route without
the key and with CORS, so a web page can fetch it directly. It's a separate
switch on purpose: turning it on publishes what you're listening to at a URL
anyone holding the link can poll. A key can't be the answer for a public page,
because the page would have to embed it.

## Limits worth knowing

- **The PC must be awake and signed in, with Issun, Tailscale and Discord
  desktop running.** The real cost of avoiding self-botting. Issun clears
  presence after 90s of silence rather than leaving a stale song up.
- **Apple Music only.** `MPMusicPlayerController.systemMusicPlayer` sees the
  built-in Music app and nothing else. System-wide now-playing lives behind the
  private MediaRemote framework, which is entitlement-gated.
- **Sideloading is permanent.** The silent-audio keepalive is an App Review
  violation on its own — the `audio` background mode is for apps that actually
  play something — and no legitimate background mode delivers 30-second updates.
  This can never ship on the App Store, and that's a deliberate trade, not an
  oversight.
- **Background survival is best-effort.** The silent audio holds the app alive
  only while its audio session is active, and four separate things stop it: an
  interruption, a media services reset, a configuration change when the audio
  route switches (AirPods, headphones, CarPlay), and a session that simply
  refuses to activate. `KeepAlive` handles all four, retries instead of giving
  up, and re-checks `engine.isRunning` every 10 seconds — and reports all of it
  so a failure shows up in the log rather than as unexplained silence. It still
  dies on force quit. `SilenceWatchdog` notifies you 15 minutes after check-ins
  stop, which survives force quit, eviction and reboot because the notification
  is already queued with iOS.
- **Cloud tracks are inconsistent.** `nowPlayingItem` is reliable for library
  content and usually fine for streamed catalog tracks, but does return nil
  sometimes. The 5s poll covers missed notifications, not nil.
- **Artwork needs a catalog match or an upload.** Issun tries an exact lookup
  by `playbackStoreID` first, then a cover uploaded by the phone, then fuzzy
  iTunes search. Plenty of independent releases aren't in the iTunes Store
  search index at all, which is why the first two paths exist.

## Files

```
project.yml                     XcodeGen spec — no .xcodeproj is committed
.github/workflows/build-ipa.yml CI producing the unsigned, versioned IPA
Ammy/
  AmmyApp.swift                 SwiftUI entry point and settings screen
  PresenceController.swift      Wires playback changes to pushes
  NowPlayingMonitor.swift       MediaPlayer observation, store ID + cover art
  PresenceRelay.swift           HTTPS client for the endpoint
  KeepAlive.swift               Silent audio to survive backgrounding
  Diagnostics.swift             The phone's self-report, sent with every push
  SilenceWatchdog.swift         Notification for when the app isn't running
  EventLog.swift                What happened to the link, kept for History
  LinkHistoryView.swift         The History screen
```

`CLAUDE.md` carries the design decisions and the traps already paid for. Read it
before changing anything non-obvious.
