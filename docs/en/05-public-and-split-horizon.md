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

## 3. Mikrotik split-horizon

```
/ip dns static add name=paperless.nb3.me address=192.168.5.200 comment="k8s VIP"
/ip dns static add name=navidrome.nb3.me address=192.168.5.200 comment="k8s VIP"
```

(One entry per service; a regexp wildcard `.*\\.nb3\\.me` would also catch
`ssh-agent.nb3.me` and break the SSH tunnel — don't.)

## 4. Verify both paths

```bash
# LAN (resolves to VIP, cert = Let's Encrypt wildcard):
dig +short paperless.nb3.me @192.168.5.1     # -> 192.168.5.200
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
