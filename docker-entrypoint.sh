#!/bin/sh
# WebLinked is configured with command-line flags. Unraid's template UI, and
# most container UIs, offer environment variables and nothing else — so a
# template without this shim has to put the entire command line into one
# "Post Arguments" blob, which is neither discoverable nor validatable.
#
# Env vars are translated to flags here and placed BEFORE "$@", so anything
# passed explicitly on the command line still has the last word. Unset vars
# contribute nothing: WebLinked's own defaults apply.
set -eu

ARGS=""

# Note the `if`: under `set -e`, a bare `[ -n "$x" ] && add ...` whose test
# fails makes the whole compound return non-zero and kills the script.
add_if_set() {
  eval "_v=\${$1:-}"
  if [ -n "$_v" ]; then
    ARGS="$ARGS $2=$_v"
  fi
}

add_if_true() {
  eval "_v=\${$1:-}"
  if [ "$_v" = "true" ]; then
    ARGS="$ARGS $2"
  fi
}

add_if_set WEBLINKED_URL      --url
add_if_set WEBLINKED_FORMAT   --format
add_if_set WEBLINKED_NDI_NAME --ndi
add_if_set WEBLINKED_OMT_NAME --omt
add_if_set WEBLINKED_PORT     --port
add_if_set WEBLINKED_OSC_PORT --osc-port
add_if_set WEBLINKED_TOKEN    --token
add_if_set WEBLINKED_CACHE    --cache
add_if_set WEBLINKED_NAME     --name
add_if_true WEBLINKED_ALPHA    --alpha
add_if_true WEBLINKED_NO_AUDIO --no-audio

# Advertising is on by default in WebLinked itself, so this only ever turns it
# off — hence "0" rather than the add_if_true pattern above. Worth having in a
# container because the advertisement cannot work on bridge networking anyway,
# and a record nothing can reach is noise on whatever network it does reach.
if [ "${WEBLINKED_MDNS:-}" = "0" ] || [ "${WEBLINKED_MDNS:-}" = "false" ]; then
  ARGS="$ARGS --no-mdns"
fi

# A missing NDI runtime is a normal state, not a fault — the process starts and
# reports the backend unavailable. Saying so here saves reading the API to find
# out why no source ever appeared on the network.
if [ -n "${WEBLINKED_NDI_NAME:-}" ] && ! ls /opt/ndi/lib/libndi.so.6* >/dev/null 2>&1; then
  echo "weblinked: NDI requested, but no libndi.so.6 is mounted at /opt/ndi/lib." >&2
  echo "weblinked: the NDI output will report itself unavailable. See the README." >&2
fi

# The three switches after --ozone-platform are the whole headless story; drop
# any of them and Chromium exits with "Missing X server or \$DISPLAY".
# Order is: ours, then env-derived, then whatever the user passed — so an
# explicit flag always beats an environment variable.
# shellcheck disable=SC2086 -- ARGS is deliberately word-split into flags.
exec /app/weblinked \
  --ozone-platform=headless \
  --use-gl=angle --use-angle=swiftshader \
  --bind "${WEBLINKED_BIND:-0.0.0.0}" \
  --no-settings \
  $ARGS "$@"
