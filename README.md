> [!IMPORTANT]
> **This packaging has moved into [WebLinked](https://github.com/stoatworks-labs/weblinked)
> itself**, under [`docker/`](https://github.com/stoatworks-labs/weblinked/tree/main/docker),
> and the image is now published as **`ghcr.io/stoatworks-labs/weblinked`** — `:edge` from
> `main`, `:X.Y.Z` from each release, `:sha-*` per commit. The docs are
> [docker/README.md](https://github.com/stoatworks-labs/weblinked/blob/main/docker/README.md).
>
> **`ghcr.io/stoatworks-labs/weblinked-docker:edge` no longer updates.** It is frozen at a build of WebLinked as of 22 August 2026 (just after v1.0.1),
> and this repository is archived. Change any compose file or Unraid template to
> `ghcr.io/stoatworks-labs/weblinked:edge`.

> **AI-assisted project.** This packaging was created with [Claude](https://claude.com/claude-code)
> (Anthropic), directed and reviewed by a human author. **The NDI output has never been received
> from this image**, because libndi is not in it and is not ours to ship.

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

**A URL in. NDI out. No display, no card, no desktop.**

## Moving to the new name

Change the image and nothing else — the mounts, ports, flags and `WEBLINKED_*`
variables are the same:

```diff
-    image: ghcr.io/stoatworks-labs/weblinked-docker:edge
+    image: ghcr.io/stoatworks-labs/weblinked:edge
```

The NDI runtime is still yours to supply, mounted at `/opt/ndi/lib`, and host
networking is still required for NDI discovery.

## Why it moved

The Dockerfile here cloned WebLinked's `main` at build time, and that layer was a
cache hit on every run — so `:edge` quietly stayed on WebLinked as of 22 August
2026, just after v1.0.1, through six releases. Built from WebLinked's own
checkout, every change to the source reaches the image, and the image carries the
version it was built from in its `com.stoatworks.weblinked.version` label.

Three things are different in the new image, all described in its README: the
KMS and RTMP/SRT outputs are built off; the healthcheck now honours
`WEBLINKED_TOKEN`, `WEBLINKED_BIND` and `WEBLINKED_PORT`; and the docs no longer
claim mDNS discovery works in a container — this image never had avahi support,
whatever this README used to say about mounting the avahi socket.

## What is left here

The old `Dockerfile`, entrypoint and workflow, unchanged, the Unraid template
under `unraid/`, and the history. The packaging is no longer developed here;
issues belong on [WebLinked](https://github.com/stoatworks-labs/weblinked/issues).

## Licence

MIT, matching WebLinked itself. NDI® is a registered trademark of Vizrt NDI AB
(<https://ndi.video>); this project neither includes nor distributes any part of the
NDI SDK.
