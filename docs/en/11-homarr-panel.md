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

## Boards (created in the Homarr UI)

Boards, apps and integrations live in Homarr's SQLite DB on the Longhorn
volume `homarr-database`, not in git. Recreate them from this table:

| Board | Access | Contents |
|---|---|---|
| `public` | public; home board for anonymous visitors | Navidrome `music`, Immich `photos`, Seafile `sync` |
| `remote` | private; the user's default board | everything; UniFi -> `https://unifi.ui.com/consoles/<console-id>` |
| `lan` | private | everything; UniFi -> `https://192.168.1.1` |

Groups on the private boards: public (Navidrome, Immich, Seafile), personal
(Syncthing UI, Paperless), auxiliary (Grafana, monitoring, Home Assistant,
UniFi). Every cluster app uses its `https://<name>.nb3.me` URL on every board:
the same name resolves to the VIP on the LAN and to Cloudflare outside.

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
   build the three boards, set `public` as the home board for anonymous users.

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
