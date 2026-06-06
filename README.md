# netbug_k3s — Homelab Kubernetes (2026 rebuild)

**Русская версия: [README.ru.md](README.ru.md)**

A two-node K3s cluster on x86 mini-PCs in a home LAN, managed entirely through GitOps.

## Stack

| Concern | Choice |
|---|---|
| Distribution | [K3s](https://k3s.io) — 1 server (embedded etcd) + 1 agent |
| GitOps | [Flux CD](https://fluxcd.io) v2.8 — this repo is the source of truth |
| Routing | Gateway API v1.5 + Traefik v3 (Flux-managed; k3s-bundled traefik disabled) |
| LoadBalancer | MetalLB (L2) — stable VIP on the LAN |
| Storage | Longhorn (replicated across nodes); large media via NFS (csi-driver-nfs) |
| TLS | cert-manager, wildcard `*.nb3.me` via Cloudflare DNS-01 |
| Public access | Cloudflare Tunnel (in-cluster cloudflared) — no open ports |
| LAN access | Split-horizon DNS on Mikrotik → MetalLB VIP, same hostnames |
| Secrets | SOPS + age, decrypted by Flux |
| External DNS/tunnels | OpenTofu in the separate `nb3_tf` repo |

## Repository layout

```
clusters/homelab/     Flux entrypoint: flux-system + ordered Kustomizations
infrastructure/
  sources/            HelmRepositories
  crds/               Gateway API CRDs
  controllers/        metallb, traefik, cert-manager, longhorn, csi-driver-nfs, cloudflared
  config/             shared Gateway, wildcard Certificate, media NFS PV
apps/                 one directory per service (the "service module")
cluster-setup/        k3s config.yaml for each node (applied manually at install)
docs/en, docs/ru      numbered per-milestone guides
```

## The service module

Each app under `apps/<name>/` is self-contained:

| File | Purpose |
|---|---|
| `ks.yaml` | Flux Kustomization (SOPS decryption, dependsOn infrastructure) |
| `namespace.yaml` | dedicated namespace |
| `helmrelease.yaml` | upstream chart, or [bjw-s app-template](https://bjw-s-labs.github.io/helm-charts/) |
| `httproute.yaml` | `HTTPRoute` → shared Gateway, hostname `<app>.nb3.me` |
| `pvc.yaml` | Longhorn PVC(s) for state |
| `secret.sops.yaml` | app secrets (optional) |

Adding a new service:
1. `cp -r` an existing app dir, adjust names/chart/hostname
2. Add one line to `apps/kustomization.yaml`
3. Add one entry to `k8s_services` in `nb3_tf/terraform.tfvars` → `tofu apply` (public DNS + tunnel route)
4. Add a Mikrotik static DNS entry `<app>.nb3.me → <VIP>` (LAN path)

## Guides

| # | EN | RU |
|---|---|---|
| — | [Architecture](docs/architecture.md) | [Архитектура](docs/architecture.ru.md) |
| 01 | [Cluster setup](docs/en/01-cluster-setup.md) | [Установка кластера](docs/ru/01-cluster-setup.md) |
| 02 | [kubectl access](docs/en/02-kubectl-access.md) | [Доступ kubectl](docs/ru/02-kubectl-access.md) |
| 03 | [GitOps & infrastructure](docs/en/03-gitops-infra.md) | [GitOps и инфраструктура](docs/ru/03-gitops-infra.md) |
| 04 | [First workload: Paperless](docs/en/04-paperless.md) | [Первый сервис: Paperless](docs/ru/04-paperless.md) |
| 05 | [Public access & split-horizon](docs/en/05-public-and-split-horizon.md) | [Публичный доступ и split-horizon](docs/ru/05-public-and-split-horizon.md) |
| 06 | [Navidrome & media over NFS](docs/en/06-navidrome-media.md) | [Navidrome и медиа по NFS](docs/ru/06-navidrome-media.md) |
| 07 | [Second node](docs/en/07-second-node.md) | [Второй узел](docs/ru/07-second-node.md) |
