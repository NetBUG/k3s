# 05 — Public access (Cloudflare Tunnel) & LAN split-horizon

> Milestone M5. Result: `paperless.nb3.me` works identically off-LAN
> (Cloudflare edge) and on-LAN (direct to the VIP) — same hostname, valid TLS
> on both paths.

## How the two paths fit together

See [architecture.md](../architecture.md#two-access-paths-one-hostname).
Key constraint: nb3.me has `always_use_https=on` (required by the existing SSH
tunnel — **never change it**), so the LAN path must terminate TLS with the
wildcard cert from milestone 03. Do not enable HSTS at the Cloudflare edge
until both paths are verified.

## 1. Terraform (nb3_tf)

Everything is already declared in `k8s_services.tf` + `terraform.tfvars`
(`k8s_services` map: paperless, navidrome, k3s-api). Run with your env tokens:

```bash
cd ../nb3_tf
export TF_VAR_cloudflare_api_token=... TF_VAR_cloudflare_api_nb3_token=...
tofu plan    # MUST show only creations — zero changes to ssh* or zone settings
tofu apply
```

Created: tunnel `k8s-homelab`, remote-managed ingress rules (hostname →
`https://traefik.traefik.svc.cluster.local:443` with Host/SNI set to the public
hostname), proxied CNAMEs → `<tunnel-id>.cfargotunnel.com`.

## 2. Feed the tunnel token to the cluster

```bash
tofu output -raw k8s_tunnel_token   # base64 token for `cloudflared tunnel run`
cd ../Ste30_k3s/netbug_k3s/infrastructure/controllers/cloudflared
kubectl create secret generic tunnel-token -n cloudflared \
  --from-literal=TUNNEL_TOKEN="$(cd ../../../../nb3_tf && tofu output -raw k8s_tunnel_token)" \
  --dry-run=client -o yaml > secret.sops.yaml
sops -e -i secret.sops.yaml         # then uncomment it in kustomization.yaml
git add -A && git commit -m "Add tunnel token" && git push
```

cloudflared connects outbound; check: `kubectl -n cloudflared logs deploy/cloudflared`
should show 4 edge connections registered.

## 3. Split-horizon on the Ubiquiti router

The VIP is `192.168.1.100` (outside the DHCP range), announced over ARP by
sowilo's MetalLB speaker on `enp1s0` only — see
`infrastructure/config/metallb-pool.yaml`. node01 is a libvirt guest behind NAT
and can never announce a LAN address.

The records are maintained by ExternalDNS
(`infrastructure/controllers/external-dns`): every HTTPRoute hostname gets an
A record on the router (UniFi Network ≥ 10.3.58, DNS Policies API, API key)
pointing at the Gateway address, plus a `k8s.homelab.a-<name>` TXT ownership
record. A new app's LAN record appears when its HTTPRoute merges. Records it
does not own are never touched. Expected result:

| Name | Address |
|---|---|
| `music.nb3.me` | `192.168.1.100` |
| `photos.nb3.me` | `192.168.1.100` |
| `sync.nb3.me` | `192.168.1.100` |
| `paperless.nb3.me` | `192.168.1.100` |
| `grafana.nb3.me` | `192.168.1.100` |
| `ha.nb3.me` | `192.168.1.100` |
| `home.nb3.me` | `192.168.1.100` |

Names without an HTTPRoute are left out automatically: `k3s` and `ssh-*`.
`ha` and `home` have HTTPRoutes and get records too (see
[11](11-homarr-panel.md)). Never add a wildcard by hand: it would also catch
`ssh-agent.nb3.me` and break the SSH tunnel.

On the LAN, Grafana is reached without Cloudflare Access (only Grafana's own
login) — intentional, so dashboards stay usable during a WAN outage.

Clients that do not use the router's DNS (a VPN-pushed resolver, browser DoH)
do not see these records; give such a machine the same names in `/etc/hosts`.

## 4. Verify both paths

```bash
# LAN path without DNS (works before the router records exist):
curl -sI --resolve paperless.nb3.me:443:192.168.1.100 https://paperless.nb3.me
arp -n 192.168.1.100                         # -> sowilo's MAC (b4:2e:99:2c:55:11)

# LAN (resolves to VIP, cert = Let's Encrypt wildcard):
dig +short paperless.nb3.me @192.168.1.1     # -> 192.168.1.100
curl -v https://paperless.nb3.me 2>&1 | grep -E "subject|issuer"

# Public (force resolution through Cloudflare):
dig +short paperless.nb3.me @1.1.1.1         # -> CF edge IPs
curl -v --resolve paperless.nb3.me:443:$(dig +short paperless.nb3.me @1.1.1.1 | head -1) \
  https://paperless.nb3.me 2>&1 | grep -E "subject|issuer"

# Remote kubectl (see 02): cloudflared access tcp --hostname k3s.nb3.me --url 127.0.0.1:6443

# The SSH tunnel must still work:
cloudflared access ssh --hostname ssh-agent.nb3.me
```

Next: [06 — Navidrome & media](06-navidrome-media.md)
