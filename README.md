# weblinked-docker

> [!WARNING]
> **This is designed to run purely inside a [Tailscale](https://tailscale.com) tailnet (or
> another private network you trust end to end). Do not expose it to the public internet.**
> The control API has no authentication until you set `--token`, and `POST /api/script`
> **runs arbitrary JavaScript in the rendered page** — an unauthenticated port here is
> remote code execution in a browser on your network, not merely a feed someone can
> retune. Its security has **not** been independently reviewed by a human. This image
> binds `0.0.0.0` by default and runs with host networking, so it is on every interface
> the server has. Set `WEBLINKED_BIND` to your tailnet address, set a token, and keep it
> off the open internet. No reverse proxy, no port forward, no "it's fine, it has a
> password".

> **AI-assisted project.** This packaging was created with [Claude](https://claude.com/claude-code)
> (Anthropic), directed and reviewed by a human author. The image has been built
> and run: it renders real pages headless at 1080p50 with zero dropped ticks, and
> [WebLinked](https://github.com/stoatworks-labs/weblinked)'s 89-test suite passes
> inside it — the first time that suite has ever run on Linux. **The NDI output
> has never been received from this image**, because libndi is not in it and is
> not ours to ship. Everything below the NDI line is verified; the NDI line
> itself is not. [What is actually verified](#what-is-actually-verified) is
> specific about which is which.

**A URL in. NDI out. No display, no card, no desktop.**

[WebLinked](https://github.com/stoatworks-labs/weblinked) renders a web page
offscreen at a broadcast raster and exact frame rate and sends it out as video.
This repository is the container for the part of it that makes sense on a
server: point it at a dashboard, a scoreboard or a clock, and it becomes an NDI
source your vision mixer, decoder or recorder can take.

```bash
docker run -d --name weblinked --network host \
  -v /mnt/user/appdata/weblinked/ndi:/opt/ndi/lib:ro \
  ghcr.io/stoatworks-labs/weblinked-docker:edge \
  --url 'https://grafana.example/public-dashboards/abc123' \
  --format 1080p50 --ndi=Grafana
```

---

## What is in here, and what cannot be

| Output | In the image | Why |
|---|---|---|
| **NDI** | Yes (needs a mounted runtime) | The point of the exercise |
| **OMT** | Yes | Compiled in, but has never been tested against any receiver |
| Preview + HTTP/OSC control | Yes | The control page is the whole UI |
| DeckLink, AJA | **No** | SDI wants a card and a kernel driver on the host |
| Syphon / Spout | **No** | macOS and Windows respectively; Linux has no equivalent |
| Fullscreen screen output | **No** | Needs X11 and a GPU-attached display, which a server has not got |

Chromium renders through **SwiftShader on the CPU**, deliberately — no GPU
passthrough, no `/dev/dri`, nothing to arrange on the host. A dashboard is
nowhere near heavy enough to want a GPU.

## The NDI runtime is not in this image, and you have to supply it

`libndi` is loaded with `dlopen` at run time, by design — WebLinked never links
it. Its licence permits redistribution only under terms forbidding modification
and reverse engineering, which MIT cannot impose, so **baking it into a public
image would be a licence violation, not a packaging shortcut.**

Without it, the container still starts, still serves the control page, and
simply reports the NDI backend unavailable. To get NDI:

1. Download the **NDI SDK for Linux** from [ndi.video](https://ndi.video/for-developers/ndi-sdk/)
   and accept their licence yourself. It is free, and gated behind an email.
2. Take `libndi.so.6` (and the symlinks beside it) out of `lib/x86_64-linux-gnu/`.
3. Put them in a directory on the host and mount it at `/opt/ndi/lib`:

```bash
-v /mnt/user/appdata/weblinked/ndi:/opt/ndi/lib:ro
```

`LD_LIBRARY_PATH` in the image already includes that path. Confirm it took:

```bash
curl -s http://localhost:7654/api/state | grep -o '"compiled_backends":[^]]*]'
```

## Host networking is not optional for NDI

**NDI discovery is mDNS.** On Docker's bridge network the sender is invisible to
every receiver on the LAN — it does not error, it just never appears. Use
`--network host`, or run an NDI Discovery Server and point both ends at it.

The same applies to **WebLinked's own advertisement**. From 0.8.0 it publishes
its control API as `_weblinked._tcp` so rookery and the Companion module can
find it, and that is mDNS too: on bridge networking it never reaches the LAN.
It needs three things in this image, and it is worth knowing that missing any
of them costs you discovery and nothing else — the container runs, and the
control API works perfectly for anyone who types the address:

- **`--network host`**, as above.
- **avahi-daemon reachable**, since Linux registration goes through it. This
  image does not run one; mount the host's socket
  (`-v /var/run/avahi-daemon/socket:/var/run/avahi-daemon/socket`) and have
  avahi running on the host.
- **`WEBLINKED_BIND` not left on loopback.** WebLinked deliberately refuses to
  advertise while its control API is bound to `127.0.0.1`, because the record
  would resolve, on every machine that browses, to that machine's own loopback.
  It logs the reason, and `/api/settings` reports it.

Set `WEBLINKED_MDNS=0` to switch the advertisement off — appropriate where
multicast is filtered, or where the container is reached only over a tailnet
and the record would be noise that never arrives.

On host networking the container binds the host's ports directly: **7654/tcp**
for the control page and API, **7655/udp** for OSC. Change them with `--port`
and `--osc-port` if something else already has them.

### Keeping it on the tailnet

Host networking means the control port is on **every** interface the server has,
including whatever faces your LAN. Two things narrow that, and you want both:

- **`WEBLINKED_BIND`** — a literal address to bind, e.g. `100.64.0.5`. Unlike
  unfuckarr there is no interface-name form: WebLinked's `--bind` takes an
  address, so use the tailnet IP. Because host networking puts the container in
  the host's network namespace, the host's `tailscale0` address is directly
  bindable; Unraid's per-container Tailscale toggle also works.
- **`WEBLINKED_TOKEN`** — required on every HTTP request once set. Set it even
  on a tailnet, because `/api/script` is arbitrary code execution in the page.

A container on the default bridge network cannot see the host's `tailscale0` at
all — but bridge networking breaks NDI discovery anyway, so that combination is
not one to reach for here.

## Pointing it at Grafana

Grafana's own auth will not follow an offscreen browser that cannot be typed
into, so give it a URL that needs no login. In order of preference:

- **A public dashboard** — Dashboard → Share → Public dashboard. Read-only, one
  dashboard, no server-wide change. This is the one to use.
- **Anonymous viewer access** (`GF_AUTH_ANONYMOUS_ENABLED=true`,
  `GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer`) if the Grafana is on a trusted network
  and you would rather not mint links per dashboard.

Add `&kiosk` to drop Grafana's chrome, and `&refresh=10s` to keep the panels
moving. WebLinked repeats the last frame between changes, so a slow refresh
costs nothing in output pacing — the feed stays at rate either way.

## Configuration

Everything is a command-line flag, appended after the image name; see
[WebLinked's docs](https://github.com/stoatworks-labs/weblinked/blob/main/docs/00-overview.md).
The ones that matter here:

| Flag | Does |
|---|---|
| `--url <url>` | The page. Default `about:blank` |
| `--format <spec>` | `1080p50`, `720p59.94`, `1920x1080i25`. Default `1080p50` |
| `--ndi[=name]` | NDI sender name. Default `WebLinked` |
| `--alpha` | Send BGRA with the page's alpha intact |
| `--port <n>` | Control HTTP port. Default 7654 |
| `--token <secret>` | Require a token on every HTTP request |
| `--cache <dir>` | Persist cookies and storage. Give each instance its own |
| `--name <text>` | What this instance calls itself when it advertises. Default: host and port |
| `--no-mdns` | Do not advertise over mDNS (see host networking, above) |

The environment variables the entrypoint understands map one to one onto those:
`WEBLINKED_URL`, `WEBLINKED_FORMAT`, `WEBLINKED_NDI_NAME`, `WEBLINKED_OMT_NAME`,
`WEBLINKED_PORT`, `WEBLINKED_OSC_PORT`, `WEBLINKED_TOKEN`, `WEBLINKED_CACHE`,
`WEBLINKED_NAME`, `WEBLINKED_BIND`, `WEBLINKED_ALPHA`, `WEBLINKED_NO_AUDIO`, and
`WEBLINKED_MDNS=0`.

The entrypoint already supplies `--ozone-platform=headless`, `--use-gl=angle`,
`--use-angle=swiftshader`, `--bind 0.0.0.0` and `--no-settings`. The first three
are what make Chromium render with no display at all; without them it exits with
`Missing X server or $DISPLAY`.

## Building it yourself

```bash
docker build -t weblinked-docker .
```

Roughly 20 minutes and ~4 GB of scratch space: it downloads a 315 MB pinned CEF
distribution, compiles WebLinked and CEF's wrapper, and **runs the unit tests as
a build step** — a failing suite fails the build. The result is ~1.9 GB, most of
it Chromium.

`--build-arg WEBLINKED_REF=v0.7.1` pins a tag instead of tracking `main`.

## What is actually verified

Measured inside this image on a 24-core host, at 1080p50:

- **50.1 ticks/sec, 0 dropped ticks**, 289 µs clock lateness.
- **97% of ticks carried a fresh paint** on a full-screen `requestAnimationFrame`
  animation; the rest repeated the previous frame, which is what SwiftShader
  costs on a pathological page. A dashboard is far lighter.
- Real pages render correctly — fonts, gradients, web CSS, 0 console errors.
- **89 tests, 25,225 checks, 0 failures.**

Not verified, and you should assume nothing:

- **No NDI receiver has ever seen output from this image.** No libndi, no test.
- **OMT has never been tested against a receiver** anywhere in the project.
- Audio rides along with the frames but has not been checked here.
- `frames_overwritten` climbs roughly in step with `frames_published`, which
  under external pacing should stay near zero. It may be a counter that means
  something different from what its name suggests; it has not been chased down.
  See [issues](https://github.com/stoatworks-labs/weblinked/issues).

## Licence

MIT, matching WebLinked itself. NDI® is a registered trademark of Vizrt NDI AB;
this project neither includes nor distributes any part of the NDI SDK.
