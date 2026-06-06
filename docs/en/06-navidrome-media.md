# 06 — Second workload: Navidrome + media over NFS

> Milestone M6. Result: Navidrome streams the music collection; the pod can
> run on either node. Demonstrates the media-mount variant of the service module.

## Why NFS for the big collections

The music/media collections are too large (and too cold) for Longhorn
replication — they stay on the media node's disk. Options considered:

| Option | Verdict |
|---|---|
| **NFS export + csi-driver-nfs static PV** | ✅ chosen — any node mounts it, pods stay mobile; RO for players, RWX possible later for Nextcloud |
| hostPath + nodeAffinity | ❌ welds the pod to the media node — defeats the mobility requirement |
| SMB (csi-driver-smb) | fallback only if the share must also serve Windows clients natively; Mikrotik/macOS clients can use NFS or the existing LAN SMB separately |
| Copy into Longhorn | ❌ doubles/triples storage for write-once data |

Heavier media workloads (SMB server, Nextcloud, transcoding bots) can stay
*off-cluster* on the media node; the cluster only mounts what it needs.

## 1. NFS export on the media node

```bash
sudo apt install -y nfs-kernel-server
echo '/export/media 192.168.5.0/24(ro,no_subtree_check,all_squash,anonuid=1000,anongid=1000)' \
  | sudo tee -a /etc/exports
# Bind the real collection into the export tree (survives reboots via fstab):
echo '/srv/music /export/media/music none bind 0 0' | sudo tee -a /etc/fstab
sudo mkdir -p /export/media/music && sudo mount -a
sudo exportfs -ra && sudo exportfs -v
```

`ro` at the export level — the strongest guarantee for the music collection.
A future RW share (Nextcloud) gets its *own* export line with `rw` and a
dedicated subtree.

## 2. Cluster side (already in git)

- `infrastructure/config/media-nfs-pv.yaml` — static PV `media-music-ro`
  (driver `nfs.csi.k8s.io`, `ReadOnlyMany`, mount options `ro,nfsvers=4.1`).
  **TODO check**: server IP matches the media node.
- `apps/navidrome/` — the module: Longhorn PVC for `/data`, `music-ro` PVC
  bound to the static PV, mounted read-only at `/music`.

```bash
git push && flux reconcile ks apps --with-source
```

## 3. Verify

```bash
kubectl -n navidrome get pvc                  # music-ro Bound to media-music-ro
kubectl -n navidrome exec deploy/navidrome -- ls /music | head
curl -v https://navidrome.nb3.me              # LAN; library scan finds the files

# Mobility check (the actual requirement):
kubectl -n navidrome get pod -o wide          # note the node
kubectl drain <that-node> --ignore-daemonsets --delete-emptydir-data
kubectl -n navidrome get pod -o wide          # rescheduled on the other node, still streams
kubectl uncordon <that-node>
```

(Note: if Navidrome lands on the media node itself, NFS loopback-mounts —
fine for RO traffic at this scale.)

Next: [07 — Second node](07-second-node.md)
