# Notes

Working notes for this repo: status, decisions, and the traps that have actually bitten.
Migrated out of Claude Code's memory on 2026-08-24, so they are written in the first
person and dated by when each thing was learned — that date is usually the useful part.

Cross-cutting notes that are not specific to this repo live in
[fleet-notes](https://github.com/stoatworks-labs/fleet-notes).

*weblinked-docker — PUBLIC container for WebLinked's headless NDI path; Linux build works, libndi must never be baked in*

`~/Projects/weblinked-docker` — **github.com/stoatworks-labs/weblinked-docker, PUBLIC,
MIT, created 2026-08-10.** Packaging only, **no source**: the Dockerfile clones
[weblinked](https://github.com/stoatworks-labs/weblinked/blob/main/docs/NOTES.md) (`weblinked`) at build time (`WEBLINKED_REF`, default `main`). Image
`ghcr.io/stoatworks-labs/weblinked-docker:edge`, ~1.9 GB, **verified public and
anonymously pullable**. Built and run on lilnasX (Unraid 7.2, 24 cores).

**WebLinked's Linux port was a non-event — zero source changes.** Its docs said
"expect to do work here"; that was pessimistic. Three fixes, all packaging:

- `cannot find -lX11` → `libx11-dev`. **CEF links X11 even with
  `-DWEBLINKED_WITH_SCREEN=OFF`** — the option does not remove `-lX11`.
- A wall of `undefined reference to dbus_/snd_/atk_/NSS_/ipp` → Chromium's
  runtime `-dev` libs. **This is libcef.so's own DT_NEEDED entries**, not our
  code, and it reads like a broken CEF distribution.
- `Missing X server or $DISPLAY`, then ANGLE demanding X anyway →
  `--ozone-platform=headless --use-gl=angle --use-angle=swiftshader`. All three
  are required; drop any one and it exits at startup. WebLinked's own arg parser
  passes unknown Chromium flags straight through to CEF.

**89 tests, 25,225 checks, 0 failures on Linux** — the suite's first ever run
there. Measured in-container: **50.1 ticks/sec at 1080p50, 0 dropped ticks**,
289 µs lateness, ~97% of ticks carrying a fresh paint under SwiftShader (CPU
rendering, no GPU passthrough needed).

**libndi must NEVER be baked into the image.** It is dlopen'd, and its licence
forbids the modification/RE that MIT cannot forbid — so it is mounted at
`/opt/ndi/lib` (already on `LD_LIBRARY_PATH`) from a directory the user
downloads themselves. Absence is a normal state: the process starts and reports
the backend unavailable. See [ndi distribution licensing](https://github.com/stoatworks-labs/fleet-notes/blob/main/notes/reference_ndi_distribution_licensing.md).

**Host networking is a correctness flag** — NDI discovery is mDNS, which
Docker's bridge network does not forward, silently.

**An entrypoint shim translates `WEBLINKED_*` env vars to flags**, because
WebLinked takes CLI arguments and Unraid's template UI offers only variables.
Env-derived flags go *before* `"$@"` so explicit args win. Watch two traps that
bit during writing: `[ -n "$x" ] && add …` under `set -e` kills the script when
the var is unset (use `if`), and an inline `python3 -c` heredoc at column 0
**terminates a YAML block scalar** — that broke the workflow file itself, so the
smoke assertion lives in `scripts/smoke_assert.py`.

**Verified vs assumed:** the render path is verified end to end (real Grafana
page, correct fonts/gradients, 0 console errors). **NDI is entirely unverified —
no receiver has ever seen a frame from this image**, because the runtime is not
in it. OMT untested anywhere. `WEBLINKED_BIND=127.0.0.1` verified to refuse from
outside while the container still reports healthy.

**Open bug, upstream:** `frames_overwritten` climbs roughly 1:1 with
`frames_published`. Under external pacing one tick should mean one paint and
that counter should stay near zero. Seen on a pathological rAF page; may be
benign, may mean the Linux paint path delivers differently. Not chased.

Also fixed here: **`cmake/FetchCEF.cmake` upstream pins only macosarm64**, so a
Linux build through its own fetch path downloads 315 MB unverified and merely
warns. The linux64 sha1 is `341947ed007fb5ddbcf9dfb33db0cf4866ffa1ec` (CEF
150.0.17+chromium-150.0.7871.187); linuxarm64 is
`6fb359a22c8fc60243f836133997d06584fc0d8d`.

CA entry lives in [stoatworks unraid](https://github.com/stoatworks-labs/stoatworks-unraid/blob/main/docs/NOTES.md) (`stoatworks-unraid`), never here — new kind
`cpp-service`, host network, ports 7654/tcp + 7655/udp, all three `hasOwn*`
flags set. Carries the same tailnet-only warning as [unfuckarr](https://github.com/stoatworks-labs/unfuckarr/blob/main/docs/NOTES.md) (`unfuckarr`) for a
sharper reason: **`POST /api/script` runs arbitrary JavaScript in the page**, so
an exposed control port is RCE in a browser on the network.
