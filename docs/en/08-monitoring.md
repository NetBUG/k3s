# 08 — Monitoring: hardware metrics with VictoriaMetrics

> Milestone M8. Result: VictoriaMetrics stack in-cluster, Grafana at
> `grafana.nb3.me` (LAN-only), and real temperature/CPU/RAM from the bare-metal
> hosts — not just the VMs.

## Why bare metal

The k3s nodes are KVM **guests**; hypervisors don't pass host thermal sensors
into a VM, so an in-cluster exporter reports CPU/RAM but **no temperature**.
Real temps come from `node-exporter` running on the physical machines. Two
collection paths, one backend:

| Target | Exporter | Temp? |
|---|---|---|
| k8s nodes (node1, node2…) | chart DaemonSet | no (guest) |
| 192.168.0.237 / .162 (KVM hosts, amd64) | systemd `node-exporter` | yes — `coretemp`/`k10temp` |
| 192.168.0.69 (ARM board) | systemd `node-exporter` | yes — `thermal_zone` |
| 192.168.0.92 (Linux NAS) | systemd `node-exporter` | yes — `hwmon`/`thermal` |

Backend is `victoria-metrics-k8s-stack` (vmsingle + vmagent + Grafana +
kube-state-metrics + node-exporter + vmalert + alertmanager) — ~5–10× lighter
on RAM than kube-prometheus-stack, which matters on the 2 GiB node.

## 1. Set the Grafana admin password (SOPS)

```bash
# edit the password, then encrypt in place with the cluster age key:
$EDITOR infrastructure/controllers/monitoring/grafana-admin.sops.yaml
sops --encrypt --in-place infrastructure/controllers/monitoring/grafana-admin.sops.yaml
```

`.sops.yaml` already matches `*.sops.yaml` and encrypts `data/stringData`; the
`infra-controllers` Kustomization decrypts it on apply. **Do not commit the
plaintext.**

## 2. Push + reconcile

```bash
git add infrastructure/sources/victoria-metrics.yaml \
        infrastructure/controllers/monitoring infrastructure/config/monitoring \
        infrastructure/{sources,controllers,config}/kustomization.yaml
git commit -m "Add VictoriaMetrics monitoring stack" && git push

flux reconcile source git flux-system
flux reconcile kustomization infra-controllers --with-source
flux reconcile kustomization infra-config --with-source
flux get helmreleases -n monitoring          # vm-stack -> Ready
kubectl -n monitoring get pods               # vmsingle/vmagent/grafana/ksm/node-exporter/vmalert/alertmanager Running
```

> CRDs: the chart ships the VM operator CRDs as plain manifests
> (`crds.plain: true`) and the HelmRelease uses `crds: CreateReplace`. If a Helm
> apply ever fails on CRD size, the fallback is to move the operator CRDs into
> `infrastructure/crds/` (same pattern as Gateway API) and disable chart CRD creation.

## 3. Install node-exporter on the bare-metal hosts

Copy the script to each host and run it (idempotent; auto-detects arch/distro):

```bash
scp scripts/install-node-exporter.sh user@192.168.0.237:/tmp/
ssh user@192.168.0.237 'sudo bash /tmp/install-node-exporter.sh'
# repeat for .162, .69, .92
```

It installs `node-exporter` (+ `lm-sensors` on x86), loads `coretemp`/`k10temp`,
enables the systemd service on `:9100`, and prints a firewall hint — allow
`tcp/9100` from `192.168.0.0/24` if the host runs ufw/firewalld.

To add/remove hosts later, edit
`infrastructure/config/monitoring/vmstaticscrape-baremetal.yaml`.

## 4. Verify

```bash
# vmagent sees all four bare-metal targets UP:
kubectl -n monitoring port-forward svc/vmagent-vm-stack 8429 &
curl -s localhost:8429/targets | grep baremetal-node
```

Open `https://grafana.nb3.me` on the LAN, log in, open **Node Exporter Full**:
each host shows temp/CPU/RAM. The in-cluster node correctly shows no temps.
Query `node_hwmon_temp_celsius` / `node_thermal_zone_temp` in Explore to confirm
non-zero readings from `192.168.0.237/.162/.69/.92`.

Grafana is **LAN-only**: it resolves via split-horizon DNS to the MetalLB VIP and
has no Cloudflare tunnel ingress, so it is not reachable from the internet.

## 5. Alerting (follow-up)

`defaultRules` + `infrastructure/config/monitoring/vmrule-hardware.yaml`
(high temp, node down, high memory) load into vmalert immediately and are visible
in the UI. Alertmanager currently routes to a no-op receiver — wire a real channel
(Telegram/email/Slack) by adding a SOPS secret and pointing `alertmanager.config`
at it.

## Scaling to node2

Nothing to do: node-exporter is a DaemonSet (auto-lands on node2) and vmagent's
Kubernetes service discovery picks the new node up automatically. Optionally bump
the vmsingle/Grafana PVCs to Longhorn 2-replica once node2 is healthy.
