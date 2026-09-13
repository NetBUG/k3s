# 06 — Second workload: Navidrome on a local hostPath library

> Milestone M6. Result: `music.nb3.me` streams the collection off sowilo's
> array. Demonstrates the node-pinned / bulk-media variant of the service
> module, and the "reuse an existing on-disk state dir" migration pattern.

## Why hostPath, not NFS

This milestone originally specified an NFS export plus a static
`csi-driver-nfs` PV, so the pod could run on either node. That export was
never built, and by the time the workload was actually deployed the premise
had gone away:

| Option | Verdict |
|---|---|
| **hostPath + nodeSelector** | ✅ chosen — the music is on sowilo's `md0` and nowhere else, so "mount from any node" was never reachable |
| NFS export + static PV | ❌ the export would live on sowilo and be loopback-mounted by a pod on sowilo: an extra service, an extra hop, and the page cache paid for twice |
| Copy into Longhorn | ❌ 131G of write-once data, replicated |

The mobility NFS buys is only worth paying for if a *second* node could serve
the library. It can't — the files are on one array on one machine. What NFS
would actually add here is a daemon that can fail independently of the thing
it serves.

The part that *is* irreplaceable — the SQLite DB with users, playlists, stars
and play counts — stays on Longhorn, where it gets a replica on node01 and can
be pushed to the R2 backup target. Navidrome also writes its own consistent
daily dump into that volume (`ND_BACKUP_*`), because a volume snapshot of a
live SQLite file is not guaranteed to be consistent.

## Layout on sowilo

| Path | What | Mounted as |
|---|---|---|
| `/media/Magic/netbug/Music/Library` | the library Navidrome scans (`md0`, 7.3T array) | `/music`, read-only |
| Longhorn PVC `navidrome-data` (5Gi) | DB, artwork cache, daily DB dumps | `/data` |
| `/media/data/navidrome` | Docker-era state, **seed source only** | not mounted |

Everything Navidrome touches is owned `1000:1000`, matching the `user: 1000:1000`
the Docker container ran as. The pod's `fsGroup: 1000` is what makes the fresh
Longhorn volume writable by that uid — it does nothing for the hostPath mount,
which is read-only and already owned correctly.

`/media/Magic/netbug/Music` also holds `_Google` (42G), `_WIP` (69G, root-owned)
and loose video files. `Library/` is deliberately a separate subtree so the
scanner sees only what belongs in it.

## 1. Prepare the host

```bash
ssh sowilo.nb3.me
mkdir -p /media/Magic/netbug/Music/Library
chown 1000:1000 /media/Magic/netbug/Music/Library
```

The mount is declared `hostPathType: Directory`, so a missing path is a loud
pod failure. With the type unset the kubelet silently creates a root-owned
empty directory and Navidrome reports a perfectly healthy library of zero
tracks.

## 2. Seed the data volume from the Docker-era DB

The old deployment (`~/compose/navidrome/`) left a 40MB `navidrome.db` in
`/media/data/navidrome`, last written 2026-06-28. Keeping it preserves the
user accounts, playlists and play history.

**Version constraint:** `latest` on that date was **0.62.0**, and Navidrome
migrations are forward-only — an older binary will not open a newer schema.
The pinned tag must stay `>= 0.62.0`; it is currently `0.63.2`.

Seed *before* enabling the app, so there is never a fresh DB to clobber:

```bash
kubectl apply -f apps/navidrome/app/namespace.yaml
kubectl apply -f apps/navidrome/app/pvc.yaml
kubectl apply -f apps/navidrome/seed-job.yaml     # one-shot, not Flux-managed
kubectl -n navidrome wait --for=condition=complete job/navidrome-seed --timeout=5m
kubectl -n navidrome logs job/navidrome-seed      # should list navidrome.db
kubectl -n navidrome delete job navidrome-seed
```

The job refuses to run if `/dst` already holds a `navidrome.db`, so a stray
re-apply cannot overwrite a live database. `/media/data/navidrome` is left
untouched on disk — that is the rollback.

Skipping the seed entirely is fine too: Navidrome creates an empty DB and you
set up a user on first login.

### What the empty library does to the seeded DB

`Library/` starts empty, so the first scan finds none of the 1574 tracks the
DB knows about. `Scanner.PurgeMissing` defaults to `never`, so those rows are
kept and listed under *Missing Files* rather than deleted. Navidrome keys
media on the path under `/music`, so if the files later land at the same
relative paths the history reattaches by itself — that is the argument for
populating `Library/` with the contents of `ARTISTS/` rather than with
`ARTISTS/` as a subdirectory.

## 3. Enable the app

`apps/kustomization.yaml` already lists `navidrome/ks.yaml`.

```bash
git push && flux reconcile ks apps --with-source
kubectl -n navidrome get pod,pvc
```

## 4. Public and LAN hostname

The service answers on `music.nb3.me`, not `navidrome.nb3.me` — the hostname
predates the k3s migration (it fronted the nginx vhost on sowilo) and the
Subsonic clients are configured with it.

**Before the first apply**, delete the stale `music.nb3.me` record in the
Cloudflare dashboard. It is a leftover of the pre-migration setup, is not in
Terraform state, and returns `530 / error 1033` today because no tunnel
ingress rule claims it. Renaming the managed `navidrome` record onto that name
collides with it.

```bash
cd ../nb3_tf
export TF_VAR_cloudflare_api_token=... TF_VAR_cloudflare_api_nb3_token=...
tofu plan     # expect: the k8s CNAME renamed navidrome -> music, plus the
              # tunnel ingress rule following it. Zero changes to ssh*.
tofu apply
```

### LAN path — nothing works here yet, for any service

Measured 2026-09-13: the Mikrotik split-horizon described in [05](05-public-and-split-horizon.md)
was never configured. `paperless.nb3.me`, `photos.nb3.me` and `music.nb3.me`
all resolve to Cloudflare edge IPs from the LAN router, so LAN clients already
leave the house and come back through the tunnel.

Pointing a static entry at the MetalLB VIP will not fix it. `192.168.122.200`
is on the **libvirt** subnet: sowilo has no interface there (only a manual
`192.168.122.0/24 via 192.168.0.26` route, whose neighbour is `INCOMPLETE`),
and the only node that could answer ARP for it is node01, which is `NotReady`.
A `curl` to the VIP *from a cluster node* succeeds regardless — kube-proxy
DNATs a LoadBalancer IP locally — so that test proves nothing about a LAN
client.

Two ways out, neither of them Navidrome-specific:

```
# A. Stopgap, works today: Traefik's NodePort on sowilo's LAN address.
/ip dns static add name=music.nb3.me address=192.168.0.92 comment="sowilo NodePort"
#    -> https://music.nb3.me:30289   (valid wildcard cert; Host and SNI match)
#    Pin the nodePort in the Traefik HelmRelease first — 30289 was auto-assigned.

# B. Proper fix: move the MetalLB pool onto 192.168.0.0/24 so sowilo's own
#    speaker announces it over enp1s0. Clean :443, no robothost, no node01.
#    .200 is taken; .201-.215 answered nothing — confirm against the DHCP pool.
```

```
/ip dns static remove [find name="navidrome.nb3.me"]
```

## 5. Verify

```bash
kubectl -n navidrome get pod -o wide            # on sowilo
kubectl -n navidrome exec deploy/navidrome -- ls /music | head
kubectl -n navidrome logs deploy/navidrome | grep -i "scan\|migrat"

curl -sI https://music.nb3.me                   # 200, not 530/404
curl -s https://music.nb3.me/ping               # Subsonic ping endpoint
```

A `530 / error 1033` means the tunnel has no ingress rule for the hostname
(check `tofu apply` ran); a `404` from Traefik means the rule exists but no
HTTPRoute matches (check the hostname in `httproute.yaml`).

## Rollback

```bash
# back to the Docker-era DB, in place:
kubectl -n navidrome delete job navidrome-seed --ignore-not-found
flux suspend hr navidrome -n navidrome
kubectl -n navidrome scale deploy navidrome --replicas=0
# re-seed: delete the PVC, re-apply pvc.yaml + seed-job.yaml, resume
```

The original `/media/data/navidrome` is never written to by the cluster.

Next: [07 — Second node](07-second-node.md)
