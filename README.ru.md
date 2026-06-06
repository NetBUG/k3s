# netbug_k3s — домашний Kubernetes (пересборка 2026)

**English version: [README.md](README.md)**

Кластер K3s из двух узлов на x86 мини-ПК в домашней сети, полностью управляемый через GitOps.

## Стек

| Задача | Решение |
|---|---|
| Дистрибутив | [K3s](https://k3s.io) — 1 server (встроенный etcd) + 1 agent |
| GitOps | [Flux CD](https://fluxcd.io) v2.8 — этот репозиторий является источником истины |
| Маршрутизация | Gateway API v1.5 + Traefik v3 (управляется Flux; встроенный в k3s traefik отключён) |
| LoadBalancer | MetalLB (L2) — стабильный VIP в локальной сети |
| Хранилище | Longhorn (реплицируется между узлами); большие медиаколлекции — NFS (csi-driver-nfs) |
| TLS | cert-manager, wildcard `*.nb3.me` через Cloudflare DNS-01 |
| Публичный доступ | Cloudflare Tunnel (cloudflared внутри кластера) — без открытых портов |
| Доступ из LAN | Split-horizon DNS на Mikrotik → VIP MetalLB, те же hostnames |
| Секреты | SOPS + age, расшифровываются Flux |
| Внешние DNS/туннели | OpenTofu в отдельном репозитории `nb3_tf` |

## Структура репозитория

```
clusters/homelab/     Точка входа Flux: flux-system + упорядоченные Kustomizations
infrastructure/
  sources/            HelmRepositories
  crds/               CRD Gateway API
  controllers/        metallb, traefik, cert-manager, longhorn, csi-driver-nfs, cloudflared
  config/             общий Gateway, wildcard-сертификат, NFS PV для медиа
apps/                 одна директория на сервис («модуль сервиса»)
cluster-setup/        k3s config.yaml для каждого узла (применяется вручную при установке)
docs/en, docs/ru      пронумерованные руководства по этапам
```

## Модуль сервиса

Каждое приложение в `apps/<name>/` самодостаточно:

| Файл | Назначение |
|---|---|
| `ks.yaml` | Flux Kustomization (расшифровка SOPS, dependsOn инфраструктуры) |
| `namespace.yaml` | отдельный namespace |
| `helmrelease.yaml` | официальный чарт или [bjw-s app-template](https://bjw-s-labs.github.io/helm-charts/) |
| `httproute.yaml` | `HTTPRoute` → общий Gateway, hostname `<app>.nb3.me` |
| `pvc.yaml` | PVC Longhorn для состояния |
| `secret.sops.yaml` | секреты приложения (опционально) |

Добавление нового сервиса:
1. `cp -r` существующей директории приложения, поправить имена/чарт/hostname
2. Добавить одну строку в `apps/kustomization.yaml`
3. Добавить запись в `k8s_services` в `nb3_tf/terraform.tfvars` → `tofu apply` (публичный DNS + маршрут туннеля)
4. Добавить статическую DNS-запись на Mikrotik `<app>.nb3.me → <VIP>` (путь через LAN)

## Руководства

| # | EN | RU |
|---|---|---|
| — | [Architecture](docs/architecture.md) | [Архитектура](docs/architecture.ru.md) |
| 01 | [Cluster setup](docs/en/01-cluster-setup.md) | [Установка кластера](docs/ru/01-cluster-setup.md) |
| 02 | [kubectl access](docs/en/02-kubectl-access.md) | [Доступ kubectl](docs/ru/02-kubectl-access.md) |
| 03 | [GitOps & infrastructure](docs/en/03-gitops-infra.md) | [GitOps и инфраструктура](docs/ru/03-gitops-infra.md) |
| 04 | [First workload: Paperless](docs/en/04-paperless.md) | [Первый сервис: Paperless](docs/ru/04-paperless.md) |
| 05 | [Public access & split-horizon](docs/en/05-public-and-split-horizon.md) | [Публичный доступ и split-horizon](docs/ru/05-public-and-split-horizon.md) |
| 06 | [Navidrome & media over NFS](docs/en/06-navidrome-media.md) | [Navidrome и медиа по NFS](docs/ru/06-navidrome-media.md) |
| 07 | [Second node](docs/en/07-second-node.md) | [Второй узел](docs/ru/07-second-node.md) |
