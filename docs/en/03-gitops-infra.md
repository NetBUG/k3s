`# 03 — GitOps bootstrap & infrastructure layer

> Milestone M3. Result: Flux reconciles this repo; Gateway, wildcard cert,
> VIP, Longhorn all green. See [architecture.md](../architecture.md) for the why.

## 1. Bootstrap Flux

```bash
flux check --pre
flux bootstrap github \
  --owner=netbug --repository=k3s \
  --branch=rebuild-2026 --path=clusters/homelab --personal
```

This commits `clusters/homelab/flux-system/` and starts reconciling everything
under `clusters/homelab/` — including `infrastructure.yaml` and `apps.yaml`.

## 2. SOPS age key (one-time, imperative)

```bash
age-keygen -o age.agekey                  # NEVER commit this file
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=age.agekey
# Put the PUBLIC key (age1...) into .sops.yaml and commit.
```

## 3. Secrets to fill in

| Secret | Where | How |
|---|---|---|
| Cloudflare DNS token (cert-manager) | `infrastructure/config/cf-api-token.sops.yaml` | copy from `.example`, fill, `sops -e -i`, uncomment in kustomization |
| Tunnel token (cloudflared) | `infrastructure/controllers/cloudflared/secret.sops.yaml` | from `nb3_tf`: `tofu output -raw k8s_tunnel_token` (see [05](05-public-and-split-horizon.md)) |

## 4. Reconciliation order

`infra-sources → infra-crds → infra-controllers → infra-config → apps`
(enforced by `dependsOn` in `clusters/homelab/infrastructure.yaml`).
MetalLB's pool and the ClusterIssuer sit in `infra-config` because they need
CRDs from the controllers layer to exist first.

## 5. Verify

```bash
flux get kustomizations          # all Ready=True
kubectl get gatewayclass,gateway -A         # traefik class; homelab Gateway Programmed
kubectl -n traefik get certificate          # wildcard-nb3-me Ready
kubectl -n traefik get svc traefik          # EXTERNAL-IP = the MetalLB VIP
kubectl get storageclass                    # longhorn (default)
```

Troubleshooting: `flux logs --level=error -A`, `flux reconcile ks <name> --with-source`.

Next: [04 — Paperless](04-paperless.md)
