#!/usr/bin/env bash
#
# install-node-exporter.sh — set up Prometheus node-exporter on a bare-metal host
# so the homelab VictoriaMetrics stack can scrape hardware metrics (temperature,
# CPU, RAM, disk, net) over :9100.
#
# Why bare metal: the k3s nodes are KVM guests and cannot read the host's thermal
# sensors. Run this on the physical machines instead:
#   192.168.0.237 (kvm-a), 192.168.0.162 (kvm-b), 192.168.0.69 (arm), 192.168.0.92 (nas)
#
# Usage (on each host):
#   sudo ./install-node-exporter.sh
#
# Idempotent: safe to re-run. Works on Debian/Ubuntu (apt) and falls back to the
# upstream binary on other distros. Detects amd64/arm64 automatically.
set -euo pipefail

NODE_EXPORTER_VERSION="1.9.1"   # fallback-binary version (Debian/Ubuntu use the distro pkg)
LISTEN_PORT="9100"

log() { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Run as root (sudo)."

ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) GOARCH="amd64" ;;
  aarch64|arm64) GOARCH="arm64" ;;
  armv7l|armv6l) GOARCH="armv7" ;;
  *) die "Unsupported architecture: $ARCH" ;;
esac
log "Architecture: $ARCH ($GOARCH)"

# ---------------------------------------------------------------------------
# 1) Install node-exporter
# ---------------------------------------------------------------------------
install_via_apt() {
  log "Debian/Ubuntu detected — installing via apt."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  # lm-sensors gives x86 CPUs their hwmon temp sensors; node-exporter ships a
  # systemd unit listening on :9100 with hwmon + thermal collectors enabled.
  apt-get install -y prometheus-node-exporter lm-sensors
  systemctl enable --now prometheus-node-exporter
  SERVICE="prometheus-node-exporter"
}

install_via_binary() {
  warn "Non-apt distro — installing upstream binary v${NODE_EXPORTER_VERSION}."
  local tarball="node_exporter-${NODE_EXPORTER_VERSION}.linux-${GOARCH}"
  local url="https://github.com/prometheus/node_exporter/releases/download/v${NODE_EXPORTER_VERSION}/${tarball}.tar.gz"
  local tmp; tmp="$(mktemp -d)"
  log "Downloading $url"
  curl -fsSL "$url" -o "$tmp/ne.tar.gz" || die "Download failed (no internet?)."
  tar -xzf "$tmp/ne.tar.gz" -C "$tmp"
  install -m 0755 "$tmp/$tarball/node_exporter" /usr/local/bin/node_exporter
  rm -rf "$tmp"

  id node_exporter &>/dev/null || useradd --no-create-home --shell /usr/sbin/nologin node_exporter

  cat >/etc/systemd/system/node_exporter.service <<'UNIT'
[Unit]
Description=Prometheus Node Exporter
After=network-online.target
Wants=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter --collector.hwmon --collector.thermal_zone
Restart=on-failure

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable --now node_exporter
  SERVICE="node_exporter"
  # Best-effort sensors package for x86 temps.
  command -v sensors >/dev/null 2>&1 || warn "lm-sensors not installed; install it for x86 CPU temps."
}

if command -v apt-get >/dev/null 2>&1; then
  install_via_apt
else
  install_via_binary
fi

# ---------------------------------------------------------------------------
# 2) Enable hardware temperature sensors
# ---------------------------------------------------------------------------
if [ "$GOARCH" = "amd64" ]; then
  # Load Intel/AMD CPU temp drivers and persist across reboots.
  log "Loading x86 CPU temperature modules (coretemp, k10temp)."
  for mod in coretemp k10temp; do modprobe "$mod" 2>/dev/null || true; done
  printf 'coretemp\nk10temp\n' >/etc/modules-load.d/node-exporter-temp.conf
  if command -v sensors-detect >/dev/null 2>&1; then
    log "Probing sensors (sensors-detect --auto)."
    sensors-detect --auto >/dev/null 2>&1 || warn "sensors-detect found nothing extra (often fine)."
  fi
else
  # ARM/SBC: temps come from /sys/class/thermal via the thermal_zone collector,
  # which is enabled by default. No module loading needed.
  log "ARM host: relying on thermal_zone (/sys/class/thermal) — no modules needed."
fi

# ---------------------------------------------------------------------------
# 3) Verify + firewall hint
# ---------------------------------------------------------------------------
sleep 1
if curl -fsS "http://127.0.0.1:${LISTEN_PORT}/metrics" >/dev/null 2>&1; then
  TEMP_COUNT="$(curl -fsS "http://127.0.0.1:${LISTEN_PORT}/metrics" \
    | grep -cE '^node_(hwmon_temp_celsius|thermal_zone_temp)' || true)"
  log "node-exporter is up on :${LISTEN_PORT} (${TEMP_COUNT} temperature series exposed)."
  [ "$TEMP_COUNT" -gt 0 ] || warn "No temp series yet — check 'sensors' output / sensor support on this host."
else
  die "node-exporter not responding on :${LISTEN_PORT}. Check: systemctl status ${SERVICE:-node_exporter}"
fi

cat <<EOF

------------------------------------------------------------------------------
Done. node-exporter is serving metrics at:  http://$(hostname -I | awk '{print $1}'):${LISTEN_PORT}/metrics

Firewall: vmagent scrapes from the cluster, whose traffic egresses as the KVM
host's LAN IP. If this host runs a firewall, allow tcp/${LISTEN_PORT} from your LAN, e.g.:

  ufw:   sudo ufw allow from 192.168.0.0/24 to any port ${LISTEN_PORT} proto tcp
  nftables/firewalld: open tcp/${LISTEN_PORT} for 192.168.0.0/24

This host's IP must be listed in:
  infrastructure/config/monitoring/vmstaticscrape-baremetal.yaml
------------------------------------------------------------------------------
EOF
