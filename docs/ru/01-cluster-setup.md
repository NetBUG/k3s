# 01 — Первоначальная установка кластера (node1)

> Этап M1. Результат: однонодовый кластер K3s, готовый к GitOps.
> Железо: x86 мини-ПК (NUC), Ubuntu 24.04 LTS, статический IP в LAN.

## 1. Подготовка узла

```bash
# Статический IP — зарезервировать в DHCP-сервере Mikrotik или настроить netplan.
# Зависимости Longhorn:
sudo apt update && sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid
```

Пакеты NFS-сервера понадобятся позже и только на узле с медиаколлекцией (см. [06](06-navidrome-media.md)).

## 2. Размещение конфигурации K3s

K3s читает `/etc/rancher/k3s/config.yaml` при старте — все флаги живут там,
а не в `INSTALL_K3S_EXEC` (современный подход; переживает переустановки и читается в git).

```bash
sudo mkdir -p /etc/rancher/k3s
sudo cp cluster-setup/node1-server-config.yaml /etc/rancher/k3s/config.yaml
# Отредактировать: указать реальный IP узла в tls-san.
```

Что отключено и почему:

| Компонент | Замена | Причина |
|---|---|---|
| `traefik` (встроенный) | Traefik v3 через Flux HelmRelease | версия закреплена в git, обновления через Renovate, провайдер Gateway API включается явно |
| `servicelb` (klipper-lb) | MetalLB | стабильный VIP, переживающий переезд подов/узлов; klipper публикует только на IP узлов |
| `local-storage` | Longhorn | реплицируемые тома, чтобы нагрузки могли переезжать между узлами |

Оставлены по умолчанию: flannel (vxlan), CoreDNS, metrics-server, встроенный etcd (через `cluster-init`).

## 3. Установка

```bash
curl -sfL https://get.k3s.io | sh -
```

## 4. Проверка

```bash
sudo k3s kubectl get nodes              # node1 Ready
sudo k3s kubectl get pods -A            # НЕТ подов traefik, svclb-*, local-path-provisioner
```

Критерий приёмки: узел `Ready`; в `kube-system` только coredns + metrics-server.

Далее: [02 — Доступ kubectl](02-kubectl-access.md)
