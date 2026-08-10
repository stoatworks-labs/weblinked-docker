#!/usr/bin/env python3
"""Assert that a running container is actually rendering.

Reads WebLinked's /api/state on stdin. A green `docker build` only proves the
image assembled; CEF failing to initialise headless is a *runtime* failure, and
this is what catches it.

Lives in a file rather than inline in the workflow because a `python3 -c`
heredoc inside a YAML block scalar has to stay indented, and Python does not
forgive that — the first version of this broke the workflow file itself.
"""

import json
import sys


def main() -> int:
    state = json.load(sys.stdin)

    pacing = state["pacing"]
    source = state["source"]

    print(
        f"format: {state['format']} | ticks: {pacing['ticks']} "
        f"| paints: {source['paints']} | dropped: {pacing['dropped_ticks']}"
    )
    print(f"backends: {state['compiled_backends']}")

    if not state["running"]:
        print("::error::the engine reports itself not running")
        return 1

    # A clock that never ticked means CEF came up but nothing drives it.
    if pacing["ticks"] < 1:
        print("::error::the clock never ticked")
        return 1

    # One paint is the initial paint of a static page. Zero means the browser
    # never rendered anything, which is the headless failure we are hunting.
    if source["paints"] < 1:
        print("::error::the browser never painted a frame")
        return 1

    # The image is pointless if the NDI backend did not compile in.
    if "ndi" not in state["compiled_backends"]:
        print("::error::the NDI backend is missing from this build")
        return 1

    print("ok: headless render path is alive")
    return 0


if __name__ == "__main__":
    sys.exit(main())
