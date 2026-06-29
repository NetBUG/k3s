# 07 — Second node: join, replicate, survive a drain

> Milestone M7. Result: 2 Ready nodes, Longhorn volumes at 2 healthy replicas,
> apps survive a node1 drain.

> **⚠️ Superseded by M9 (doc 09).** Roles later swapped: **sowilo is the server**,
> **node01 the agent**. The `node2-agent-config.yaml` referenced below was renamed
> `node01-agent-config.yaml` (and `node1-server-config.yaml` → `sowilo-server-config.yaml`).

## 1. Prepare and join node2 (agent)

```bash
# on node2:
sudo apt update && sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid

sudo mkdir -p /etc/rancher/k3s
sudo cp cluster-setup/node2-agent-config.yaml /etc/rancher/k3s/config.yaml
# fill in: server URL (node1 IP) and token from
#   node1: sudo cat /var/lib/rancher/k3s/server/node-token
curl -sfL https://get.k3s.io | sh -s - agent
```

```bash
kubectl get nodes    # node1 + node2 Ready
```

Agent (not server): with exactly two nodes a 2-member etcd is *worse* than 1
(quorum = 2, either node down halts the control plane). A future 3rd node can
join as a server — embedded etcd was chosen at install for exactly that.

## 2. Longhorn: replicas 1 → 2

Bump in git (`infrastructure/controllers/longhorn/helmrelease.yaml`):

```yaml
    persistence:
      defaultClassReplicaCount: 2
    defaultSettings:
      defaultReplicaCount: 2
```

`git push` + reconcile. **This only affects new volumes** — migrate existing
ones explicitly: Longhorn UI → Volume → each volume → *Update Replicas Count* → 2,
or:

```bash
kubectl -n longhorn-system get volumes.longhorn.io -o name |
  xargs -I{} kubectl -n longhorn-system patch {} --type=merge \
    -p '{"spec":{"numberOfReplicas":2}}'
# watch the rebuild:
kubectl -n longhorn-system get replicas.longhorn.io
```

Optional but recommended before relying on 2 replicas: configure a Longhorn
backup target (S3-compatible — Cloudflare R2 works) in the Longhorn settings.

## 3. Scale the public entry

`infrastructure/controllers/cloudflared/deployment.yaml`: `replicas: 1 → 2`
(the topologySpreadConstraint already spreads them across nodes). Push.

## 4. The final acceptance test — workload mobility

```bash
kubectl drain node1 --ignore-daemonsets --delete-emptydir-data
kubectl get pods -A -o wide               # everything lands on node2
curl -v https://paperless.nb3.me          # both paths still serve
curl -v https://navidrome.nb3.me
kubectl uncordon node1
```

What makes this work (see [architecture.md](../architecture.md)):
Longhorn volume reattaches on node2 (replica already there) · MetalLB moves the
L2 VIP announcement · cloudflared's second replica keeps the tunnel up · NFS
mounts from any node.

Caveat: if node1 is also the media node, NFS-backed apps (Navidrome) lose
media during the drain window — state on Longhorn stays intact. That's
expected: the media disk is the one deliberate single-point.
