# syntax=docker/dockerfile:1
#
# WebLinked, containerised for headless Linux.
#
# What is in here: NDI, OMT and the HTTP/OSC control API. What is not, and
# cannot be: DeckLink and AJA want a card and a kernel driver on the host, and
# the shared-surface backend is Syphon on macOS and Spout on Windows — Linux
# has neither. A container is exactly the shape of what remains.
#
# Chromium renders through SwiftShader on the CPU, deliberately. It makes the
# image portable across hosts with no GPU passthrough, and a dashboard is
# nowhere near heavy enough to want one: measured 50.1 ticks/sec at 1080p50
# with zero dropped ticks on a 24-core host.
#
# libndi is NOT baked in. It is dlopen'd at run time by design, and its licence
# forbids the modification and reverse engineering that MIT cannot forbid — so
# shipping it inside a published image is a licence problem, not a packaging
# one. Mount it instead; see the run line at the bottom.

ARG CEF_VERSION=150.0.17+g94c1726+chromium-150.0.7871.187
ARG CEF_SHA1=341947ed007fb5ddbcf9dfb33db0cf4866ffa1ec
ARG WEBLINKED_REF=main

# ---------------------------------------------------------------------------
# CEF, in its own stage so editing a source file does not re-download 315 MB.
# The hash is pinned: cmake/FetchCEF.cmake has no linux64 sha1, so an unpinned
# build downloads unverified and only warns.
# ---------------------------------------------------------------------------
FROM ubuntu:24.04 AS cef
ARG CEF_VERSION
ARG CEF_SHA1
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates bzip2 \
    && rm -rf /var/lib/apt/lists/*
RUN set -eux; \
    url_ver="$(printf '%s' "$CEF_VERSION" | sed 's/+/%2B/g')"; \
    curl -fSL -o /tmp/cef.tar.bz2 \
      "https://cef-builds.spotifycdn.com/cef_binary_${url_ver}_linux64_minimal.tar.bz2"; \
    echo "${CEF_SHA1}  /tmp/cef.tar.bz2" | sha1sum -c -; \
    mkdir -p /cef; \
    tar -xjf /tmp/cef.tar.bz2 -C /cef --strip-components=1; \
    rm /tmp/cef.tar.bz2

# ---------------------------------------------------------------------------
# Build. The -dev packages are not optional decoration: libcef.so carries
# DT_NEEDED entries for the whole Chromium runtime, and the link fails with a
# wall of "undefined reference to dbus_/snd_/atk_/NSS_" without them.
# ---------------------------------------------------------------------------
FROM ubuntu:24.04 AS build
ARG WEBLINKED_REF
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake ninja-build git python3 pkg-config ca-certificates \
        libx11-dev libxext-dev libxrender-dev libxi-dev libxtst-dev \
        libxcomposite-dev libxdamage-dev libxfixes-dev libxrandr-dev \
        libnss3-dev libatk1.0-dev libatk-bridge2.0-dev libcups2-dev \
        libdrm-dev libgbm-dev libxkbcommon-dev libpango1.0-dev libcairo2-dev \
        libasound2-dev libdbus-1-dev libglib2.0-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=cef /cef /cef
RUN git clone --depth 1 --branch "${WEBLINKED_REF}" \
        https://github.com/stoatworks-labs/weblinked.git /src
WORKDIR /src

RUN cmake -S . -B build -G Ninja \
        -DCMAKE_BUILD_TYPE=Release \
        -DCEF_ROOT=/cef \
        -DWEBLINKED_WITH_SCREEN=OFF \
        -DWEBLINKED_WITH_SHARED=OFF \
        -DWEBLINKED_WITH_DECKLINK=OFF \
        -DWEBLINKED_WITH_AJA=OFF
RUN cmake --build build -j"$(nproc)"

# The suite links weblinked_core only and needs no display. If it fails the
# image does not get built, which is the point of running it here.
RUN ./build/Release/weblinked_tests

# CEF finds its resources next to the executable, and the build leaves the
# binary one directory above them.
RUN cp build/weblinked build/Release/weblinked

# ---------------------------------------------------------------------------
# Runtime.
# ---------------------------------------------------------------------------
FROM ubuntu:24.04

# Not decoration: GHCR only links a package to its repository — and so only
# lets it be made public — when it can tell which repository built it.
LABEL org.opencontainers.image.source="https://github.com/stoatworks-labs/weblinked-docker" \
      org.opencontainers.image.description="WebLinked: renders a URL to NDI, headless" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update && apt-get install -y --no-install-recommends \
        libx11-6 libxext6 libxrender1 libxi6 libxtst6 \
        libxcomposite1 libxdamage1 libxfixes3 libxrandr2 libxcb1 \
        libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 \
        libdrm2 libgbm1 libxkbcommon0 libpango-1.0-0 libcairo2 \
        libasound2t64 libdbus-1-3 libglib2.0-0t64 libexpat1 libuuid1 \
        ca-certificates fonts-liberation fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/build/Release /app
WORKDIR /app

# no_sandbox is set in code (src/browser/cef_app.cpp), so the setuid helper is
# dead weight; the test binary has done its job at build time.
RUN rm -f /app/chrome-sandbox /app/weblinked_tests

# Where a mounted NDI runtime is looked for. libndi.so.6 is dlopen'd, so its
# absence costs the NDI output and nothing else — the process still starts and
# reports the backend unavailable.
ENV LD_LIBRARY_PATH=/app:/opt/ndi/lib

EXPOSE 7654/tcp 7655/udp

HEALTHCHECK --interval=30s --timeout=5s --start-period=25s --retries=3 \
  CMD /bin/bash -c 'exec 3<>/dev/tcp/127.0.0.1/7654 && printf "GET /api/state HTTP/1.0\r\n\r\n" >&3 && head -c 15 <&3 | grep -q 200'

# The three switches that make Chromium render with no display: headless ozone,
# and ANGLE pointed at SwiftShader so it stops trying to open an X connection.
ENTRYPOINT ["/app/weblinked", \
            "--ozone-platform=headless", \
            "--use-gl=angle", "--use-angle=swiftshader", \
            "--bind", "0.0.0.0", "--no-settings"]
CMD ["--url", "https://example.com", "--format", "1080p50"]

# Host networking is not a convenience here — NDI discovery is mDNS, and a
# bridge network hides the sender from every receiver on the LAN:
#
#   docker run -d --name weblinked --network host \
#     -v /path/to/ndi/lib:/opt/ndi/lib:ro \
#     weblinked:latest \
#     --url 'https://grafana.example/d/abc?kiosk&refresh=10s' \
#     --format 1080p50 --ndi=Grafana
