# Ammy

Apple Music on iPhone → Discord Rich Presence on a Windows desktop, via a relay
you host yourself.

```
iPhone ──https──▶ Tailscale Funnel ──▶ relay.py ──IPC──▶ Discord desktop
```

No user token, no self-botting. Discord has no Rich Presence SDK on iOS, and
setting presence from a phone directly would mean opening a Gateway WebSocket
with a user token — against ToS, and accounts get terminated for it. So the
phone never talks to Discord at all. It POSTs now-playing JSON to a relay on
your PC, and the relay uses the desktop client's local IPC socket, which is the
sanctioned path.

The cost of that design is the first limitation below, and it isn't a bug.

## Before you start

- A Windows PC that stays awake, running Discord desktop.
- Python 3.10+.
- A free **Tailscale** account. No domain, no DNS records, no port forwarding,
  and nothing exposed on your LAN.
- A **Discord** account, to create the application whose name becomes the
  "Listening to" text.
- An **Apple ID** for sideloading. A free one re-signs every 7 days.

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
RELAY_KEY=paste_a_long_random_string
PUBLIC_BASE=https://your-pc.your-tailnet.ts.net
```

A file rather than environment variables, because variables set in a PowerShell
window vanish with it — and a scheduled task inherits none of them.

`PUBLIC_BASE` is the URL you'll get from step 3, so come back and fill it in.
It's required for artwork on tracks that aren't in Apple's catalog: the phone
uploads the cover and Discord's CDN fetches it back from the relay, so the relay
has to know its own public address.

```
python bridge\relay.py
```

The relay binds to `127.0.0.1` on purpose. Nothing reaches it except through the
tunnel, and `RELAY_KEY` is checked on every request.

> `RELAY_SECRET` and the `X-Relay-Secret` header are the old names. Both are
> still read, so an existing `.env` and an older build of the app keep working.

## 3. Expose it with Tailscale Funnel

Install Tailscale on the PC and sign in. Then:

```
tailscale funnel --bg --https=443 localhost:8787
```

That prints your public URL:

```
https://your-pc.your-tailnet.ts.net
```

`--bg` is what makes it persist — Funnel resumes by itself after a reboot or a
Tailscale restart. Without it you have to re-run the command every time.

```
tailscale funnel status                      # what's currently served
tailscale funnel --bg --https=443 off        # stop serving
```

Three things have to be true on your tailnet, and Tailscale will link you
straight to whichever one is missing on first run: **MagicDNS** enabled, **HTTPS
certificates** enabled, and the `funnel` node attribute present in the policy
file. The default policy grants it to every member.

### Pin the machine name

Your URL is `https://<machine>.<tailnet>.ts.net`, and the machine half is
generated from the PC's OS hostname by default — so renaming the PC silently
moves your endpoint and the address saved in the app stops resolving. In the
admin console, open the machine and **turn off "Auto-generate from OS
hostname."** Do it before you type the URL into the phone.

The tailnet half (`tail1a2b3.ts.net`, or a word-pair if you picked one) is fixed
once HTTPS certificates have been issued for it.

Funnel can only listen on 443, 8443 and 10000 publicly. The local port it
forwards to is whatever you like; 8787 is the relay's default.

> Already have a domain and a Cloudflare account? `cloudflared tunnel run
> --url http://localhost:8787` still works fine. The relay doesn't care what's
> in front of it. Tailscale is the default here because it needs neither.

### Autostart

`bridge/install-task.ps1` registers a logon Scheduled Task. It must run in the
interactive session, not as a Windows service — Discord's IPC pipe belongs to
the logged-in session, and a session 0 task will start cleanly, listen on 8787,
and never reach Discord.

### Checking on it

```
python bridge\relay.py --version
python bridge\relay.py --summary     # phone check-in gaps over time
curl https://your-pc.your-tailnet.ts.net/version
curl -H "X-Relay-Key: your_key" https://your-pc.your-tailnet.ts.net/diag
```

`/diag` returns the phone's most recent self-report: whether the silent-audio
engine is actually running, how often it has been restarted and why, how many
audio route changes and interruptions there have been, memory footprint, and
both app and device uptime.

That report exists because **the app cannot tell you it died.** By the time
anyone notices it is gone there is nothing left running to ask. So the phone
sends its condition with every push, the relay keeps the latest one, and the
"phone stopped checking in" line in `ammy-uptime.log` carries it:

```
phone stopped checking in  last seen 17:22:13  last state: engine=no want=yes
route=BluetoothA2DP resumes=3 fails=0 heals=0 cfg=1 routechg=4 int=2/1
mem=38MB state=background lpm=no thermal=nominal appup=1840s devup=402118s
```

`engine=no want=yes` means the keepalive was already dead before the app was.
A climbing `mem` before a death means iOS reclaimed the app under memory
pressure instead — a different problem, with a different fix.

## 4. Build the IPA without a Mac

Push to `main` and the **Build unsigned IPA** workflow runs: a macOS runner
generates the Xcode project from `project.yml` via XcodeGen, compiles with
signing disabled, and uploads `Ammy-<version>-b<run>-<sha>.ipa` as an artifact.

Signing is skipped because the sideloader re-signs with your Apple ID at install
time. That also means no certificates in CI secrets.

macOS runner minutes bill at 10× on private repos. A public repo is free.

## 5. Install

Download the artifact and sideload it with **SideStore**. The upload uses
`archive: false`, so what you download is the `.ipa` itself rather than a zip
containing one — an `.ipa` is already a zip, and wrapping it in another just
adds a step. A free Apple ID means re-signing every 7 days, which SideStore
does on-device.

AltStore also works in principle, but AltServer requires iTunes *and* iCloud
direct from Apple; if you have the Microsoft Store versions installed, you'll
hit "The provided anisette data is invalid" and there is no clean way back.

## 6. Run it

In the **Endpoint** section, put your Funnel URL with `/now-playing` on the end
into **URL**, and whatever you set as `RELAY_KEY` into **Key**:

```
your-pc.your-tailnet.ts.net/now-playing
```

You can leave off `https://` — Ammy asks before adding it, rather than rewriting
what you typed behind your back, and stores the result so it only asks once.
Plain `http://` is refused outright: iOS blocks it at the network layer, and
without the explicit message that failure is indistinguishable from a relay
that's simply down.

The key is optional. Ammy will POST without it, and omits the header entirely
rather than sending an empty one — "no key configured" is a clearer signal to a
receiver than a header with nothing after it. `relay.py` refuses unauthenticated
requests, so you do need one here; a receiver of your own may not.

Tap Start, grant media library access, and allow notifications when asked.

Notifications are not optional. `UNUserNotificationCenter.add()` succeeds on an
unauthorized center and delivers nothing, so declining leaves the watchdog
silently inert rather than visibly broken.

The **Version** row on that screen shows something like `1.0 (24)` — the build
number matches the artifact name, so you can always tell which build is on the
phone.

### Shortcuts

```
ammy://music        start, then reopen Apple Music
ammy://background   start, then drop to the Home Screen
```

Worth wiring `ammy://music` to a Shortcuts automation on **Music is opened**.
Nothing restarts Ammy after a reboot or a force quit, and that automation closes
the gap.

## Reading the feed yourself

Discord doesn't have to be the only consumer. The same path serves both
directions — the phone POSTs to `/now-playing`, and anything else can GET it:

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
  "links": { "song": "https://music.apple.com/…", "album": "https://music.apple.com/…" }
}
```

It's a projection, not the raw push — the ~80KB of base64 artwork and the whole
diagnostics block are deliberately left out, and a GET never triggers an
outbound iTunes lookup, so nobody can use the endpoint to make your machine
issue traffic. Artwork and links come from cache or are omitted.

Set `PUBLIC_READ=1` in `.env` to serve this route without the key and with CORS,
so a web page can fetch it directly. It's a separate switch on purpose: turning
it on publishes what you're listening to at a URL anyone holding the link can
poll. A key can't be the answer for a public page, because the page would have
to embed it.

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
- **Artwork needs a catalog match or an upload.** Exact lookup by
  `playbackStoreID` first, then a cover uploaded by the phone, then fuzzy iTunes
  search. Plenty of independent releases aren't in the iTunes Store search
  index at all, which is why the first two paths exist.

## Files

```
project.yml                     XcodeGen spec — no .xcodeproj is committed
.github/workflows/build-ipa.yml CI producing the unsigned, versioned IPA
bridge/relay.py                 Desktop relay + Discord IPC client
bridge/install-task.ps1         Registers the logon Scheduled Task
bridge/ipc_test.py              Minimal pypresence test, no HTTP layer
Ammy/
  AmmyApp.swift                 SwiftUI entry point and settings screen
  PresenceController.swift      Wires playback changes to relay pushes
  NowPlayingMonitor.swift       MediaPlayer observation, store ID + cover art
  PresenceRelay.swift           HTTPS client for the relay
  KeepAlive.swift               Silent audio to survive backgrounding
  Diagnostics.swift             The phone's self-report, sent with every push
  SilenceWatchdog.swift         Notification for when the app isn't running
```

`CLAUDE.md` carries the design decisions and the traps already paid for. Read it
before changing anything non-obvious.
