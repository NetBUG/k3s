# 01 — Initial cluster setup (node1)

> Milestone M1. Result: a single-node K3s cluster, ready for GitOps.
> Hardware: x86 mini-PC (NUC), Ubuntu 24.04 LTS, static LAN IP.

## 1. Prepare the node

```bash
# Static IP — reserve it in the Mikrotik DHCP server, or configure netplan.
# Longhorn prerequisites:
sudo apt update && sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid
```

NFS server packages are needed later only on the media node (see [06](06-navidrome-media.md)).

## 2. Place the K3s config

K3s reads `/etc/rancher/k3s/config.yaml` at start — all flags live there,
not in `INSTALL_K3S_EXEC` (the modern idiom; survives reinstalls and is reviewable in git).

```bash
sudo mkdir -p /etc/rancher/k3s
sudo cp cluster-setup/node1-server-config.yaml /etc/rancher/k3s/config.yaml
# Edit: set the real node IP in tls-san.
```

What is disabled and why:

| Component | Replacement | Reason |
|---|---|---|
| `traefik` (bundled) | Traefik v3 via Flux HelmRelease | version pinned in git, Renovate updates, Gateway API provider enabled explicitly |
| `servicelb` (klipper-lb) | MetalLB | stable VIP that survives pod/node moves; klipper exposes on node IPs only |
| `local-storage` | Longhorn | replicated volumes so workloads can move between nodes |

Kept defaults: flannel (vxlan), CoreDNS, metrics-server, embedded etcd (via `cluster-init`).

## 3. Install

```bash
curl -sfL https://get.k3s.io | sh -
```

## 4. Verify

```bash
sudo k3s kubectl get nodes              # node1 Ready
sudo k3s kubectl get pods -A            # NO traefik, svclb-*, local-path-provisioner pods
```

Acceptance: node `Ready`; only coredns + metrics-server in `kube-system`.

Next: [02 — kubectl access](02-kubectl-access.md)
