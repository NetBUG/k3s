# Session — Homelab monitoring stack (VictoriaMetrics + node-exporter)

## Goal
Set up hardware monitoring (temperature/CPU/RAM) for the homelab, primary focus
on physical machines (amd64 + arm64), via the existing K3s/Flux GitOps flow,
ready for a second node.

## Key decisions
- **Two collection paths.** K3s nodes are KVM guests → cannot read host thermal
  sensors. Real temps require `node-exporter` on **bare metal**, not just an
  in-cluster DaemonSet. (Confirmed: hypervisors don't pass thermal data to VMs.)
- **Backend: `victoria-metrics-k8s-stack` v0.85.0** over kube-prometheus-stack —
  ~5–10× less RAM, decisive on the 2 GiB `node1` VM. Bundles vmsingle, vmagent,
  Grafana, kube-state-metrics, node-exporter, vmalert, alertmanager.
- **All targets are Linux** → all run node-exporter; no SNMP/mktxp needed.
- **Grafana LAN-only** by omitting a Cloudflare tunnel ingress (split-horizon DNS
  → MetalLB VIP only).
- **CRDs** via chart `crds.plain: true` + HelmRelease `crds: CreateReplace`;
  fallback documented (move to `infrastructure/crds/` like Gateway API).

## Inventory wired
| Host | IP | Arch | Temp source |
|---|---|---|---|
| KVM host A | 192.168.0.237 | amd64 | coretemp/k10temp |
| KVM host B | 192.168.0.162 | amd64 | coretemp/k10temp |
| ARM board | 192.168.0.69 | arm64 | thermal_zone |
| Linux NAS | 192.168.0.92 | — | hwmon/thermal |
| node1 (+node2) | 192.168.122.x | amd64 VM | none (guest) |

## Files added
- `infrastructure/sources/victoria-metrics.yaml` (+ kustomization entry)
- `infrastructure/controllers/monitoring/` — namespace, helmrelease (vm-stack),
  grafana-admin.sops.yaml (plaintext template — user must encrypt), kustomization
- `infrastructure/config/monitoring/` — vmstaticscrape-baremetal, grafana-httproute
  (grafana.nb3.me → vm-stack-grafana:80), vmrule-hardware, kustomization
- `scripts/install-node-exporter.sh` — arch/distro-aware bare-metal installer
- `docs/en/08-monitoring.md`, `docs/ru/08-monitoring.md`

## Validation done
- `kubectl kustomize` builds clean for all touched dirs.
- `helm template ... --version 0.85.0` with the exact values block → **RENDER OK**.
- Confirmed referenced names against rendered output: Service `vm-stack-grafana`
  and datasource `VictoriaMetrics` (prometheus-type, used by dashboard 1860).

## Remaining manual steps (user)
1. Edit + `sops --encrypt --in-place` the grafana-admin secret.
2. `git push` + `flux reconcile` (infra-controllers, infra-config).
3. Run `scripts/install-node-exporter.sh` on .237/.162/.69/.92; open `:9100` on
   each firewall to the LAN.

## Follow-ups / not done
- Alertmanager routes to a no-op receiver — wire a real channel (Telegram/email)
  via SOPS secret + `alertmanager.config`.
- Router monitoring deferred (would need snmp_exporter/mktxp, not node-exporter).
- Logs (Loki) intentionally out of scope; stack leaves room for it.
- node2: zero-touch (DaemonSet + SD); optionally bump PVCs to 2 Longhorn replicas.
