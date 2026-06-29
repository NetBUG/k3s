# 09 — Move the control-plane to sowilo (node01 → agent)

> Milestone M9 — **DONE (2026-06-29).** Result: **sowilo is the k3s server**
> (control-plane + embedded etcd), **node01 is a plain agent** (now cordoned —
> see the disk note below). The control-plane no longer lives on the flaky
> `robothost` guest, so a node01/robothost outage costs only an agent — not the
> API server.
>
> **Method actually used: Path 1 — snapshot-restore.** sowilo was brought up as a
> *fresh single-member* server restored from node01's etcd snapshot. The
> originally-planned Path 2 (online promotion via a 2-member etcd window) was
> **abandoned at pre-flight**: robothost turned out to be in an active crash loop
> from a **failing NVMe** (see "Why Path 1"), and a node01 crash inside the
> 2-member quorum window would have halted the control-plane.

## Why

node01 is a libvirt guest on `robothost`. It was **both** the sole control-plane
**and** half the ingress, so every robothost blip took the API server (and
`kubectl`, Flux, alerting) down. sowilo is a stable LAN host with 15 GiB RAM where
the data and workloads already live. Putting the control-plane there is the single
biggest stability win short of a 3rd server.

The control-plane stays **single-member** either way (HA needs a 3rd server,
M-future) — this just moves it onto the reliable node.

## Why Path 1 (not the planned Path 2)

Pre-flight on 2026-06-29 found robothost **crashing ~hourly** (5 boots that day,
one mid-pre-flight) with **`critical medium error, dev nvme0n1` ×152** in the
kernel log. nvme0n1 is the **single** disk holding robothost's OS *and* node01's VM
image. The thermal fix from the earlier session was working (`x86_pkg_temp 60°C`,
`cpu-fan-control.service` active), so the crashes were **disk failure**, not heat.

Path 2 passes through a 2-member embedded etcd (quorum 2): if node01 crashed in
that window — which it would, given the disk — the control-plane halts. Path 1
never depends on node01 staying up, and gets etcd onto sowilo's healthy disk
immediately. (The original Path 2 write-up is preserved in git history if needed.)

## What changed vs. what didn't

The API server moved from **`192.168.122.135`** (node01, libvirt NAT) to
**`192.168.0.92`** (sowilo, LAN). Updated: the cert SAN and any pinned kubeconfig.
**Unchanged:** cluster state (rides in etcd, restored from snapshot), the in-cluster
`cloudflared` tunnel for `k3s.nb3.me` (dials `kubernetes.default.svc`, a Service —
server-agnostic, so laptop kubectl kept working), Flux/GitOps, Longhorn data, and
**all network plumbing** — sowilo's `192.168.122.0/24 via 192.168.0.162` route and
robothost's FORWARD/POSTROUTING rules stayed; only the server/agent roles swapped.

> **The token is the linchpin.** k3s stores the cluster CA + service-account keys as
> *bootstrap data inside etcd*, encrypted with the cluster token. Restoring the
> snapshot onto sowilo only works if sowilo uses node01's **original token** — a
> mismatch makes the snapshot unusable. After the restore, sowilo's `node-token`
> came out **identical** to node01's, confirming the CA was preserved (so existing
> kubeconfigs/agent certs stayed valid; node01 rejoined with the same token string).

## Pre-flight (done first, all off the failing disk)

```bash
# Snapshot, pulled node01 -> sowilo over the STABLE LAN/libvirt route (not the
# flaky cloudflared tunnel), sha256-verified at every hop; 2nd copy to laptop.
ssh ssh-node.nb3.me 'sudo k3s etcd-snapshot save --name pre-m9-final'
# stage readable, then from sowilo: scp netbug@192.168.122.135:/tmp/... ~/m9/

# Cluster token (decrypts the restored bootstrap/CA) — REQUIRED:
ssh ssh-node.nb3.me 'sudo cat /var/lib/rancher/k3s/server/token'   # K10...::server:...

# Baseline for acceptance: 2 nodes, 13 ns, 7 PV, 61 pods.
```

## Step 1 — freeze node01 (downtime window starts)

```bash
ssh ssh-node.nb3.me 'sudo systemctl stop k3s && sudo systemctl disable k3s'
# API now down. node01 is only STOPPED, not wiped — rollback = `systemctl enable --now k3s`.
```

## Step 2 — bring sowilo up as a fresh server, restored from the snapshot

Write sowilo's **server** `config.yaml` (`cluster-init: true`, the **node01 token**,
`node-ip: 192.168.0.92`, `tls-san` incl. `192.168.0.92` + `k3s.nb3.me` + `127.0.0.1`,
disables traefik/servicelb/local-storage, `flannel-backend: vxlan`). Then:

```bash
# on sowilo:
sudo /usr/local/bin/k3s-agent-uninstall.sh
sudo mkdir -p /etc/rancher/k3s && sudo cp sowilo-server-config.yaml /etc/rancher/k3s/config.yaml

# CRITICAL: install with SKIP_START so k3s does NOT generate a fresh CA before the
# restore (a fresh CA would conflict with the snapshot's CA). Same version.
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION=v1.35.5+k3s1 INSTALL_K3S_SKIP_START=true sh -s - server

# First etcd op is the restore (token comes from config.yaml):
sudo k3s server --cluster-reset --cluster-reset-restore-path=/path/pre-m9-final.db
#   -> "kvstore restored", "Updating bootstrap data on disk from datastore"
#      (CA from the snapshot becomes authoritative; the fresh tls dir is backed up),
#      "Managed etcd cluster membership has been reset, restart without --cluster-reset".
sudo systemctl start k3s
```

> The agent-uninstall wipes containerd's image store, so **every image re-pulls**
> on sowilo afterward (slow on the N3160). Expect a few minutes of mass
> `ContainerCreating` before things settle.

## Step 3 — verify (acceptance #1)

```bash
# Locally on sowilo (tunnel may be reconnecting): sudo k3s kubectl get nodes
#   -> only sowilo, ROLES control-plane,etcd. node01's old Node object auto-removed
#      (its etcd member was pruned by cluster-reset).
# etcd single member: journal shows recovered peer https://192.168.0.92:2380.
# Objects intact vs baseline: 13 ns / 7 PV / 61 pods. Cert SANs include the new addr.
curl -sI https://photos.nb3.me                 # 200 — public ingress fine
KUBECONFIG=~/.kube/homelab.yaml kubectl get nodes   # laptop tunnel works again
```

## Step 4 — rejoin node01 as a plain agent

```bash
# node01 agent config.yaml: server https://192.168.0.92:6443 ; token <same as before> ;
#   node-ip 192.168.122.135
ssh ssh-node.nb3.me 'sudo /usr/local/bin/k3s-uninstall.sh'    # full wipe of the old server
# place agent config, then:
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION=v1.35.5+k3s1 sh -s - agent
# node01 registers as `Ready <none>` in <30s. node01->sowilo:6443 via NAT egress;
# sowilo->node01 pods via the unchanged libvirt route.
```

## Outcome / acceptance

```
NAME     STATUS                     ROLES                VERSION
node01   Ready,SchedulingDisabled   <none>               v1.35.5+k3s1   (cordoned — see below)
sowilo   Ready                      control-plane,etcd   v1.35.5+k3s1
```

`photos.nb3.me` = 200, laptop kubectl via `k3s.nb3.me` works, 59/61 pods Running.
The "control-plane survives node01 loss" property was **proven during steps 1–4**:
node01 was fully stopped the whole time and sowilo served photos + kubectl
throughout — no separate reboot test needed.

## node01's disk corrupts images → cordon + targeted exclusions

The mass image re-pull onto node01 after the agent rejoin produced **`exec format
error`** on several freshly-pulled binaries (metallb-speaker, csi-node-driver-registrar,
metallb/frr-k8s — even `/bin/sh` corrupt). Same arch (amd64), multi-arch images with
amd64 present, other containers run fine — so it's **data corruption on node01's
disk** (qcow on robothost's dying NVMe), not an arch mismatch. A clean `crictl rmi`
+ re-pull fixed speaker and csi-nfs-node but **frr-k8s reproduced the corruption** →
not a one-off, the disk is the cause.

Decision (operational):

- **`kubectl cordon node01`** → `Ready,SchedulingDisabled` (no new workloads).
- **Longhorn `nodes.longhorn.io/node01 allowScheduling=false`** (node + disks) → no
  replicas land on the bad disk; volumes stay at **1 healthy replica on sowilo**
  (status `degraded`, stable — no rebuild thrash). R2 off-site backup is the
  durability backstop.
- The two **crashlooping DaemonSets** are kept off node01 (the healthy ones —
  node-exporter, longhorn-manager, metallb-speaker, csi-nfs-node — stay):
  - `metallb-frr-k8s`: durable via a **Flux `postRenderers` kustomize patch** in
    `infrastructure/controllers/metallb/helmrelease.yaml` (nodeAffinity NotIn node01).
  - `longhorn-csi-plugin`: **live `kubectl patch`** on the DaemonSet
    (nodeAffinity NotIn node01). It is *not* in git because longhorn-manager creates
    this DaemonSet at runtime (it isn't in the Helm chart manifests, so a postRenderer
    can't reach it). Re-apply if longhorn-manager/Longhorn-upgrade reverts it.

## Rollback

The pre-flight snapshot lives on sowilo (`~/m9/pre-m9-final.db`) + the laptop. To go
back to the node01-server layout: stop k3s on sowilo, and on node01
`k3s server --cluster-reset --cluster-reset-restore-path=<pre-m9 snapshot>`, then
re-add sowilo as an agent.

## Open follow-ups

- **Replace robothost's NVMe** — the root cause. Until then node01 is best left
  cordoned/untrusted for storage.
- After the disk is fixed: un-cordon node01, re-enable its Longhorn disk, drop the
  metallb `postRenderers` block and the longhorn-csi-plugin live patch, and let
  Longhorn rebuild the 2nd replica.
- HA of the control-plane still needs a **3rd server** (out of scope).
- Optionally drop `192.168.122.135` from sowilo's `tls-san` now that node01 is gone
  as a server.
