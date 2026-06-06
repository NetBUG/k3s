# Architecture

> Русская версия: [architecture.ru.md](architecture.ru.md)

## Topology

```
                       Internet
                          │
              ┌── Cloudflare edge (TLS) ──┐
              │   paperless.nb3.me CNAME  │
              │   <tunnel>.cfargotunnel   │
              └────────────┬──────────────┘
                           │ outbound-only tunnel
   LAN 192.168.x.0/24      │
  ┌────────────────────────┼──────────────────────────┐
  │                        ▼                          │
  │   node1 (server)   cloudflared pod                │
  │   ┌──────────────┐     │ http_host_header         │
  │   │ k3s: etcd,   │     ▼                          │
  │   │ api, coredns │  Traefik v3  ◄── MetalLB VIP ──┼── LAN clients
  │   └──────────────┘  (Gateway API)  192.168.5.200  │   (Mikrotik DNS:
  │   node2 (agent)        │                          │   *.nb3.me → VIP)
  │   ┌──────────────┐     ▼ HTTPRoute per app        │
  │   │ longhorn     │  paperless · navidrome · …     │
  │   │ replica #2   │     │            │             │
  │   └──────────────┘  Longhorn PVC  NFS (media,RO)  │
  └───────────────────────────────────────────────────┘
```

## Two access paths, one hostname

| Path | DNS | TLS | Flow |
|---|---|---|---|
| Public | Cloudflare: `<app>.nb3.me` CNAME → tunnel | CF edge cert; CF→origin uses the Gateway's Let's Encrypt cert (`origin_server_name` set in nb3_tf, no `noTLSVerify`) | client → CF edge → tunnel → cloudflared pod → Traefik :443 → HTTPRoute → app |
| LAN | Mikrotik static DNS: `<app>.nb3.me` → MetalLB VIP | Let's Encrypt wildcard `*.nb3.me` (cert-manager DNS-01) | client → VIP → Traefik :443 → HTTPRoute → app |

Split-horizon constraint: the nb3.me zone has `always_use_https=on` (required by
the SSH tunnel — do not change), so browsers are sent to HTTPS even on the LAN
path. **The Gateway must therefore always hold a valid wildcard cert.** Do not
enable HSTS at the edge until the LAN cert path is verified.

## GitOps flow

```
git push ──► GitHub ──► Flux source-controller
                            │
        ┌───────────────────┼─────────────────┐
        ▼                   ▼                 ▼
  infra-sources ─► infra-crds ─► infra-controllers ─► infra-config ─► apps
  (HelmRepos)    (Gateway API)  (metallb,traefik,    (Gateway, cert,  (one Flux
                                cert-manager,        MetalLB pool,    Kustomization
                                longhorn, nfs-csi,   media NFS PV)    per app)
                                cloudflared)
```

Secrets are SOPS+age encrypted in git; Flux decrypts with the `sops-age` secret
(created once, imperatively — the private key never enters git).

## Workload mobility (the core requirement)

A workload moves between nodes without losing access because every layer is
node-independent:

1. **State** — Longhorn replicates volumes to both nodes; on reschedule the
   volume attaches wherever the pod lands. Media is NFS — mountable from any node.
2. **Routing** — HTTPRoute → Service → pod IP; Traefik follows endpoints automatically.
3. **LAN entry** — MetalLB VIP fails over between nodes (L2 announcement moves).
4. **Public entry** — cloudflared dials *out* from whichever node its pod runs on;
   Cloudflare never needs to know node IPs.

## External state split

| Where | What |
|---|---|
| this repo | everything inside the cluster |
| `nb3_tf` (OpenTofu) | Cloudflare: tunnel, per-service CNAMEs, zone settings |
| Mikrotik | DHCP reservations, split-horizon static DNS entries |
| node disks | `/etc/rancher/k3s/config.yaml` (copies in `cluster-setup/`), NFS export |

## Component inventory

| Component | Version | Why |
|---|---|---|
| K3s | latest stable channel | single binary, embedded etcd, lab-friendly |
| Flux | v2.8 | reconciles this repo into the cluster |
| Gateway API CRDs | v1.5.1 standard | HTTPRoute is Standard-channel — no experimental CRDs |
| Traefik | chart 40.2.0 / v3.7 | Gateway API provider, replaces k3s-bundled traefik |
| MetalLB | 0.16.1 | L2 VIP for LAN entry |
| cert-manager | 1.20.2 | wildcard `*.nb3.me` via Cloudflare DNS-01 |
| Longhorn | 1.12.0 | replicated storage; default StorageClass |
| csi-driver-nfs | 4.13.2 | mounts the media NFS export |
| cloudflared | 2026.5.2 | outbound tunnel for public access |
| bjw-s app-template | 4.6.2 | the Helm chart behind each service module |

Decisions of note:
- **Embedded etcd over SQLite** — a second *server* node can join later without
  datastore migration.
- **Flux-managed Traefik over k3s-bundled** — version pinned in git, Renovate
  bumps, Gateway API provider enabled explicitly instead of HelmChartConfig.
- **app-template for both apps** — there is no maintained upstream Paperless
  chart; one chart pattern keeps service modules uniform.
- **TCPRoute not used** — still Experimental channel; remote kubectl goes
  through a cloudflared TCP ingress instead.
