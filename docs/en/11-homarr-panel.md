# 11 — Homarr panel (home.nb3.me) and Home Assistant behind Traefik

> Result: one panel hostname for LAN and WAN. Anonymous WAN visitors see the
> public board, LAN devices land on the LAN board, and the logged-in user sees
> everything from anywhere. Home Assistant joins the Gateway like any other app.

## How a request is classified

Every request through the Cloudflare tunnel carries `Cf-Ray`. Cloudflare adds
it at the edge and re-adds it if a client sends an empty one, so a WAN client
cannot remove it. LAN requests arrive at the MetalLB VIP without it. The
HTTPRoute (`apps/homarr/app/httproute.yaml`) uses that:

| Request | Result |
|---|---|
| `GET /` with `Cf-Ray` (WAN) | Homarr home: public board, or the user's default board after login |
| `GET /` without `Cf-Ray` (LAN) | `302 /boards/lan` |
| any other path | Homarr |

A LAN client that fakes `Cf-Ray` only gets the WAN behaviour. Verified
2026-10-13 with a temporary `traefik/whoami` route: WAN `X-View: wan`, LAN
`lan`, LAN + fake header `wan`, WAN + empty header still `wan`.

The redirect is the only network-aware piece. Homarr itself cannot trust a
proxy header for login, so the LAN board still needs a login, once per device
(`AUTH_SESSION_EXPIRY_TIME: 365d`).

## Boards (`apps/homarr/panel.yaml`)

Boards, apps and group membership are declared in `apps/homarr/panel.yaml`
and applied by `apps/homarr/sync.py` through the Homarr API. Homarr's DB (the
Longhorn volume `homarr-database`) holds the applied copy; re-running the
script rebuilds every managed board, so tiles added in the UI to those boards
are dropped. Boards and apps not named in the file are left alone.

| Board | Access | Groups |
|---|---|---|
| `public` | public; home board for anonymous visitors | Public: Navidrome, Immich, Seafile |
| `remote` | private; the user's default board | Public; Personal: Paperless; Auxiliary: Grafana, Home Assistant, UniFi Cloud |
| `lan` | private; LAN `/` redirects here | Public; Personal: Syncthing, Paperless; Auxiliary: Grafana, Home Assistant, UniFi |

Syncthing (`http://192.168.1.125:8384`, Docker on sowilo) and the UniFi
console (`https://192.168.1.1`) have no WAN route, so they appear only on
`lan`. The repo is public, so the UniFi cloud console URL comes from the
environment, not the file:

```bash
cd apps/homarr
export HOMARR_API_KEY=...      # Homarr: Management -> Tools -> API
export UNIFI_CLOUD_URL=https://unifi.ui.com/consoles/...
./sync.py --dry-run            # reads only, prints the writes
./sync.py
```

Section and item ids are derived from board/group/app names, so a re-run
writes identical content. Tiles are 2x1 on the 12-column base layout and 1x1
on the 3-column mobile layout. The script needs PyYAML.

API notes: there is no REST read for board content; the script reads it via
the tRPC route `board.getBoardByName` with the same `ApiKey` header.
Cloudflare rejects the default `Python-urllib` User-Agent (error 1010), so
the script sends its own. `PATCH /api/boards/{id}/home` needs a `{}` body
despite the schema listing none.

## 1. Secret

```bash
cd apps/homarr/app
cp secret.sops.yaml.example secret.sops.yaml   # openssl rand -hex 32
sops -e -i secret.sops.yaml
```

Then uncomment `homarr/ks.yaml` in `apps/kustomization.yaml`. Keep a copy of
the key outside the cluster: without it, every integration secret stored in
the DB has to be re-entered.

## 2. Order of rollout

1. Push netbug_k3s. Flux creates the `homarr` and `home-assistant`
   HTTPRoutes; ExternalDNS adds `home` and `ha` LAN records on the router.
2. `tofu apply` in nb3_tf: `home` tunnel hostname + CNAME, and `ha` switched
   from `http://192.168.1.27:8123` to the Traefik origin. Applying this first
   would 404 `ha` until the HTTPRoute exists.
3. Open `https://home.nb3.me` from the LAN, create the admin user (onboarding),
   create an API key, then run `apps/homarr/sync.py`.

## Home Assistant

HA runs outside the cluster (HAOS VM `haos` on cn62). `apps/home-assistant`
gives it a selector-less Service plus an EndpointSlice for `192.168.1.27:8123`,
and an HTTPRoute for `ha.nb3.me`. Traefik (and cloudflared before it) run on
sowilo, so HA sees the same source address as before and `trusted_proxies`
needs no change. If Traefik ever schedules on node01, add that node's egress
address to `trusted_proxies`.

## Verify

```bash
dig +short home.nb3.me @192.168.1.1          # 192.168.1.100
dig +short ha.nb3.me @192.168.1.1            # 192.168.1.100
curl -sI https://home.nb3.me/ | grep -i location        # LAN: /boards/lan
curl -sI --resolve home.nb3.me:443:$(dig +short home.nb3.me @1.1.1.1 | head -1) \
  https://home.nb3.me/ | head -1                        # WAN: no redirect to /boards/lan
curl -s -o /dev/null -w '%{http_code}\n' https://ha.nb3.me/   # 200
```
