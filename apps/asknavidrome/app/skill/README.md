# Runtime patches for the AskNavidrome image

The upstream image `ghcr.io/rosskouk/asknavidrome` is used as shipped. The two
changes we need are applied at interpreter startup by `sitecustomize.py`, which
Python imports from anything on `sys.path` — `PYTHONPATH=/etc/asknavidrome-patch`
in the HelmRelease points at the ConfigMap generated from this directory.

That avoids forking the image and maintaining a registry, at the cost of being
a monkeypatch: if upstream renames what is patched, the patch logs
`FAILED: ...` on stderr and the app still starts. **Check the startup log after
any image bump.**

## What is patched

| Patch | Why |
|---|---|
| `RequestVerifier.verify` → no-op | Alexa signs HTTPS requests, but we are invoked via Lambda, which sends no `Signature` headers. `TimestampVerifier` and the `NAVI_SKILL_ID` check still run. |
| every request handler's `handle` | Upstream dereferences unfilled slots (`song.value`) in a debug f-string *before* any search, so a partially matched intent dies with `AttributeError` and the user hears a generic error. The guard answers with usable phrasing instead. |

## Verifying

Startup log should carry both lines:

```
[sitecustomize] RequestVerifier.verify neutralised for Lambda delivery
[sitecustomize] request handlers wrapped with an unfilled-slot guard
```

The guard was verified in-pod against a control — unpatched the handler raises
`'NoneType' object has no attribute 'value'`; patched it returns the spoken
guidance. When it fires in production it logs:

```
[sitecustomize] unfilled slot in <HandlerName>; answering with guidance
```

## Changing it

The interpreter imports `sitecustomize` once, so editing this file requires a
restart — Flux updating the ConfigMap is not enough:

```sh
kubectl -n asknavidrome rollout restart deploy/asknavidrome
```
