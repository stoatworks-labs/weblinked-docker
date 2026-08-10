# AGENTS.md — bringing an LLM up to speed on weblinked-docker

Orientation for an AI assistant (or a new human) picking this repository up
cold. It is small — one Dockerfile and its packaging — but three of the
decisions in it are load-bearing and look arbitrary until you know why.

## 1. What this is

The container for [WebLinked](https://github.com/stoatworks-labs/weblinked),
narrowed to what a headless server can actually do: render a URL offscreen at a
broadcast raster and send it out as NDI. **No source code lives here.** The
Dockerfile clones the upstream repository at build time (`WEBLINKED_REF`,
default `main`). If a build breaks in a way that is not about packaging, the fix
belongs upstream, not here.

## 2. The three things that are not arbitrary

**libndi is deliberately absent, and must stay absent.** WebLinked `dlopen`s it
at run time and never links it. The NDI licence permits redistribution only
under terms forbidding modification and reverse engineering — terms MIT cannot
impose — so putting it in a published image is a licence violation. The image
mounts it at `/opt/ndi/lib` instead, already on `LD_LIBRARY_PATH`. **A future
change that "conveniently" bakes the runtime in to save users a step is the one
change this repository exists to prevent.** Missing libndi is not an error
state: the process starts and reports the backend unavailable.

**The three Chromium switches in the ENTRYPOINT are the whole headless story.**
`--ozone-platform=headless` gets past `Missing X server or $DISPLAY`;
`--use-gl=angle --use-angle=swiftshader` stops ANGLE trying to open an X display
anyway and puts rendering on the CPU. Remove any one of them and the container
exits at startup. They are passed through WebLinked's own argument parser
untouched, which tolerates unknown flags and hands them to CEF.

**Host networking is a correctness flag, not a preference.** NDI discovery is
mDNS, which Docker's bridge network does not forward. On bridge the sender never
appears to any receiver and nothing anywhere reports an error.

## 3. Traps that cost real time

**The `-dev` packages in the build stage are not there to compile our code.**
`libcef.so` carries DT_NEEDED entries for the entire Chromium runtime, so the
final link fails with a wall of `undefined reference to dbus_/snd_/atk_/NSS_`
without them. The message reads like a broken CEF distribution and is not.

**CEF links X11 even with the screen output off.** `-DWEBLINKED_WITH_SCREEN=OFF`
does not remove the `-lX11` on the link line, so `libx11-dev` is required in the
builder and `libx11-6` in the runtime.

**The binary and CEF's resources must end up in the same directory.** The build
leaves `weblinked` one level above `build/Release/`, where the `.pak` files,
`icudtl.dat` and `libcef.so` are. CEF finds resources next to the executable, so
the Dockerfile copies the binary down into `Release/` before the runtime stage
takes it. Skip that and you get a browser that starts and renders nothing.

**The CEF sha1 is pinned here, not upstream.** `cmake/FetchCEF.cmake` only pins
macosarm64; a Linux build through CMake's own fetch path downloads 315 MB
unverified and merely warns. This Dockerfile downloads it itself, checks
`341947ed007fb5ddbcf9dfb33db0cf4866ffa1ec`, and passes `-DCEF_ROOT`. Bumping
`CEF_VERSION` without bumping `CEF_SHA1` from
`https://cef-builds.spotifycdn.com/index.json` will fail the build, correctly.

**amd64 only, on purpose.** arm64 would be QEMU-emulated on GitHub's runners for
a full Chromium-wrapper C++ compile — hours, for an architecture essentially
nobody runs Unraid on. `linuxarm64` CEF exists if that ever changes.

## 4. Where the Unraid template lives

**Not here.** Community Applications reads templates only from
[stoatworks-unraid](https://github.com/stoatworks-labs/stoatworks-unraid), never
from an app repository; submitting this one fails with "No ca_profile.xml
found." This app is registered there with `hasOwnDocker`, `hasOwnWorkflow` and
`hasOwnTemplate` all set, meaning the generator writes nothing into this
repository and its template is hand-maintained. Change a port or a mount here
and you must change it there too — nothing keeps them in step automatically.

## 5. What is genuinely verified vs assumed

**Verified**, by running it: the image builds; the upstream suite passes inside
it (89 tests, 25,225 checks); it renders real pages headless — correct fonts,
gradients and CSS, 0 console errors; and it holds 50.1 ticks/sec at 1080p50 with
0 dropped ticks and 289 µs lateness.

**Assumed**: everything about NDI. No receiver has ever seen a frame from this
image, because the runtime it needs is not in it. The mount path, the soname
(`libndi.so.6`) and `LD_LIBRARY_PATH` are all read off the upstream source
rather than demonstrated. OMT is worse — untested against any receiver anywhere
in the project.

**Open**: `frames_overwritten` climbs roughly one-for-one with
`frames_published`. Under external pacing one tick should mean one paint and
that counter should stay near zero. It was seen on a deliberately pathological
`requestAnimationFrame` page and may be benign, or may mean the Linux paint path
delivers differently from macOS. Nobody has chased it.
