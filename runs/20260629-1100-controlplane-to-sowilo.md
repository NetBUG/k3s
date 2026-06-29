# Session — M9: move control-plane node01 → sowilo (2026-06-29)

> **DONE.** sowilo is the k3s server (single-member etcd, healthy disk); node01 is a
> plain agent, now **cordoned + Longhorn-disabled** because its disk is failing.
> Public path up (`photos.nb3.me` 200), kubectl via tunnel works, 59/61 pods Running.

## Why the method changed (Path 2 → Path 1)

docs/09 planned **Path 2** (online: promote sowilo to 2nd server → 2-member etcd
window → drop node01). Pre-flight on 2026-06-29 found robothost in an **active
crash loop**: ~5 boots that day, crashed again mid-preflight, and the kernel log
showed **`critical medium error, dev nvme0n1` ×152** — the single boot/VM disk
(Vi3000 2TB) is failing. Thermal fix is working (`x86_pkg_temp 60°C`, fan service
active), so the crashes are now **disk**, not heat. A node01 crash inside the
2-member quorum window would halt the CP → **switched to Path 1 (snapshot-restore)**,
which never depends on node01 staying up.

## Pre-flight artifacts (off the failing disk)

- etcd snapshots pulled node01 → sowilo over the **stable LAN/libvirt route**
  (not the flaky cloudflared tunnel): `~/m9/pre-m9.db` (08:44) and
  `~/m9/pre-m9-final.db` (09:12, **used for restore**, sha `e83d5e07…`). Second
  copies on laptop scratchpad. sha256 verified at every hop.
- node01 cluster token saved (scratchpad `node01-cluster-token.txt`) —
  `K10b67899…::server:387d…`. **Required**: it decrypts the bootstrap/CA stored
  in the restored etcd; a mismatched token makes the snapshot unusable.
- sowilo→node01 ssh trust added (sowilo pubkey → node01 authorized_keys).
- Baseline for acceptance: **2 nodes, 13 ns, 7 PV, 61 pods**.

## Steps executed

0. Fresh snapshot `pre-m9-final` on node01, copied+verified to sowilo.
1. **node01**: `systemctl stop k3s && systemctl disable k3s` → API down (window start).
2. **sowilo**: `k3s-agent-uninstall.sh` → placed server `config.yaml`
   (token, `node-ip 192.168.0.92`, tls-san +192.168.0.92/k3s.nb3.me/127.0.0.1,
   `cluster-init: true`, disables traefik/servicelb/local-storage) →
   install server with **`INSTALL_K3S_SKIP_START=true`** (so no fresh CA is
   generated before restore). Version pinned `v1.35.5+k3s1`.
3. **sowilo**: `k3s server --cluster-reset --cluster-reset-restore-path=~/m9/pre-m9-final.db`.
   Log confirmed `kvstore restored current-rev 4924221`, **`Updating bootstrap
   data on disk from datastore`** (CA from snapshot became authoritative; old fresh
   tls backed up to `tls-1782732315`), `membership has been reset`. Then `systemctl start k3s`.
4. **Acceptance #1 (PASS):**
   - `kubectl get nodes`: only **sowilo Ready, control-plane,etcd**. node01 object
     auto-removed (its etcd member was pruned + not reporting).
   - etcd single member `https://192.168.0.92:2380`.
   - Objects intact vs baseline: **13 ns / 7 PV / 61 pods**.
   - apiserver cert SANs include 192.168.0.92, k3s.nb3.me, 127.0.0.1.
   - **photos.nb3.me → HTTP 200**; **laptop kubectl via k3s.nb3.me tunnel works**.
   - Pod churn = expected image **re-pull storm** (agent-uninstall wiped containerd
     store); settled to ~42 Running. Longhorn volumes `attached/degraded` (the
     node01 replica is gone) — will re-heal when node01 rejoins as agent.

## Steps 5–7 executed

5. **node01 wiped + rejoined as agent.** `k3s-uninstall.sh` → agent config
   (`server: https://192.168.0.92:6443`, sowilo node-token = **identical** to node01's
   original, confirming CA preserved; `node-ip 192.168.122.135`) → installed agent
   `v1.35.5+k3s1`. Registered as `node01 Ready <none>` in <30s. node01's old Node
   object had already auto-removed during the restore (etcd member pruned).
6. Clients: laptop tunnel unchanged (works); sowilo native kubeconfig.
   node01→sowilo:6443 via NAT egress; sowilo→node01 pods via the unchanged libvirt route.
7. **Acceptance:** both nodes Ready, sowilo `control-plane,etcd`. The "node01-down
   survives" property was already proven during steps 1–4 (node01 fully stopped,
   sowilo served photos=200 + kubectl throughout) — no separate reboot test needed.

## node01 disk corruption (the real follow-up)

After the agent rejoin, the **mass image re-pull** onto node01 (containerd store was
wiped) produced **`exec format error`** on several freshly-pulled binaries —
metallb-speaker, csi-node-driver-registrar, metallb/frr-k8s (`/bin/sh` corrupt).
speaker + csi recovered after `crictl rmi` + clean re-pull; **frr-k8s reproduced the
corruption after a clean re-pull** → not a one-off bad pull, the **node01 disk
corrupts layer data** (qcow on robothost's dying NVMe; node01 journald files also
"corrupted/uncleanly shut down"). Same arch (amd64), images are multi-arch with amd64
present, other containers run — so it's data corruption, not arch mismatch.

**Decision (user):** **cordon node01 + disable its Longhorn disk**:
- `kubectl cordon node01` → `Ready,SchedulingDisabled`.
- Longhorn `nodes.longhorn.io/node01 spec.allowScheduling=false` (node + disks).
- Effect: no new workloads/replicas land on the bad disk; node stays joined, ready
  to take work once the NVMe is replaced. Longhorn volumes stay at **1 healthy
  replica on sowilo** (status `degraded`, stable — no rebuild thrash). R2 off-site
  backup is the durability backstop.

### Stopping the two crashlooping DaemonSets on node01

cordon does NOT keep DaemonSets off a node. A blanket `NoExecute` taint would (briefly
applied, then reverted) — but it evicts the *healthy* DaemonSets too (node-exporter,
longhorn-manager, metallb-speaker, csi-nfs-node), which we keep. Targeted exclusion
of only the two crashloopers (per user) via nodeAffinity `kubernetes.io/hostname
NotIn [node01]`:

- **`metallb-frr-k8s`** — durable: Flux `postRenderers` kustomize patch in
  `infrastructure/controllers/metallb/helmrelease.yaml` (Flux reconciles the
  HelmRelease hourly, so a bare `kubectl patch` reverts — must be in git + pushed).
- **`longhorn-csi-plugin`** — **live `kubectl patch` only.** longhorn-manager creates
  this DaemonSet at runtime (not in the Helm chart manifests), so a postRenderer
  can't reach it and there's no clean GitOps hook. Re-apply if longhorn-manager or a
  Longhorn upgrade reverts it:
  `kubectl -n longhorn-system patch ds longhorn-csi-plugin --type merge -p '{"spec":{"template":{"spec":{"affinity":{"nodeAffinity":{"requiredDuringSchedulingIgnoredDuringExecution":{"nodeSelectorTerms":[{"matchExpressions":[{"key":"kubernetes.io/hostname","operator":"NotIn","values":["node01"]}]}]}}}}}}}'`

Result: node01 keeps only healthy DaemonSets; the two crashloopers run only on
sowilo. MetalLB VIP is off the critical path either way.

## Cleanup done

- Temp NOPASSWD sudoers `/etc/sudoers.d/99-m9-temp` on sowilo **removed** (sudo
  requires password again).
- Network plumbing unchanged: sowilo netplan route `192.168.122.0/24 via .162`,
  robothost FORWARD/POSTROUTING — only server/agent roles swapped.

## Docs updated (2026-06-29)

- `cluster-setup/` renamed to match reality: `node1-server-config.yaml` →
  **`sowilo-server-config.yaml`**, `node2-agent-config.yaml` →
  **`node01-agent-config.yaml`** (old files removed).
- `docs/en|ru/09` rewritten as the **Path 1 as-executed** record (+ disk-corruption
  finding, cordon, DaemonSet exclusions).
- `docs/en|ru/01,02,07` got a short "superseded by M9 / files renamed" banner (they
  describe the original node1-server build — kept as history).

## TODO (housekeeping, not blocking)

- **Replace robothost NVMe** — root cause; until then node01 is best treated as
  cordoned/untrusted for storage. After repair: un-cordon, re-enable Longhorn disk,
  drop the metallb `postRenderers` block + the longhorn-csi-plugin live patch.
- **Commit + push** branch `rebuild-2026` so Flux applies the metallb `postRenderers`
  patch durably (else it reverts on the next hourly HelmRelease reconcile).
- `README.ru.md` already had uncommitted edits (pre-existing) — review before commit.
