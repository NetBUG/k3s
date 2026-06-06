# 04 — First workload: Paperless-ngx

> Milestone M4. Result: `https://paperless.nb3.me` serves on the LAN with a
> valid certificate. This is the proving run for the **service module** pattern.

## Module anatomy (`apps/paperless/`)

```
ks.yaml                Flux Kustomization → ./apps/paperless/app (SOPS, dependsOn infra)
app/namespace.yaml     namespace `paperless`
app/pvc.yaml           3 Longhorn PVCs: data (SQLite+index), media, consume
app/helmrelease.yaml   bjw-s app-template: paperless + redis controllers
app/httproute.yaml     paperless.nb3.me → service :8000 on the shared Gateway
app/secret.sops.yaml   PAPERLESS_SECRET_KEY + admin credentials
```

Design notes:
- **app-template** rather than a service-specific chart — no maintained upstream
  Paperless chart exists; one chart keeps all modules uniform.
- **SQLite + Longhorn** instead of PostgreSQL — single-user lab; one fewer
  stateful component. The DB file lives on the replicated `data` volume.
- **Redis without persistence** — pure task broker, queue rebuilds itself.

## Deploy

```bash
# secret first:
cd apps/paperless/app
cp secret.sops.yaml.example secret.sops.yaml   # fill values
sops -e -i secret.sops.yaml                    # uncomment in kustomization.yaml
git add -A && git commit -m "Add paperless" && git push
flux reconcile ks apps --with-source
```

LAN access before milestone 05: add the Mikrotik static DNS entry
`paperless.nb3.me → 192.168.5.200` now (public path comes in [05](05-public-and-split-horizon.md)).

## Verify

```bash
flux get ks paperless                       # Ready
kubectl -n paperless get pods,pvc           # Running; PVCs Bound (longhorn)
kubectl -n paperless get httproute          # Accepted by gateway traefik/homelab
curl -v https://paperless.nb3.me            # 200/302, LE wildcard cert
```

Acceptance: login page loads over HTTPS on the LAN; document upload triggers OCR.

Next: [05 — Public access & split-horizon](05-public-and-split-horizon.md)
