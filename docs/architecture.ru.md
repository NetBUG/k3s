# Архитектура

> English version: [architecture.md](architecture.md)

## Топология

```
                       Интернет
                          │
              ┌── Cloudflare edge (TLS) ──┐
              │   paperless.nb3.me CNAME  │
              │   <tunnel>.cfargotunnel   │
              └────────────┬──────────────┘
                           │ туннель (только исходящие)
   LAN 192.168.x.0/24      │
  ┌────────────────────────┼──────────────────────────┐
  │                        ▼                          │
  │   node1 (server)   под cloudflared                │
  │   ┌──────────────┐     │ http_host_header         │
  │   │ k3s: etcd,   │     ▼                          │
  │   │ api, coredns │  Traefik v3  ◄── MetalLB VIP ──┼── клиенты LAN
  │   └──────────────┘  (Gateway API)  192.168.5.200  │   (DNS Mikrotik:
  │   node2 (agent)        │                          │   *.nb3.me → VIP)
  │   ┌──────────────┐     ▼ HTTPRoute на приложение  │
  │   │ longhorn     │  paperless · navidrome · …     │
  │   │ реплика #2   │     │            │             │
  │   └──────────────┘  Longhorn PVC  NFS (медиа,RO)  │
  └───────────────────────────────────────────────────┘
```

## Два пути доступа, один hostname

| Путь | DNS | TLS | Поток |
|---|---|---|---|
| Публичный | Cloudflare: `<app>.nb3.me` CNAME → туннель | сертификат CF edge; CF→origin использует Let's Encrypt сертификат Gateway (`origin_server_name` задан в nb3_tf, без `noTLSVerify`) | клиент → CF edge → туннель → под cloudflared → Traefik :443 → HTTPRoute → приложение |
| LAN | статический DNS Mikrotik: `<app>.nb3.me` → VIP MetalLB | wildcard Let's Encrypt `*.nb3.me` (cert-manager DNS-01) | клиент → VIP → Traefik :443 → HTTPRoute → приложение |

Ограничение split-horizon: у зоны nb3.me включён `always_use_https=on`
(нужен SSH-туннелю — не менять), поэтому браузеры уходят на HTTPS даже в LAN.
**Gateway обязан всегда держать валидный wildcard-сертификат.** Не включать
HSTS на edge, пока LAN-путь с сертификатом не проверен.

## Поток GitOps

```
git push ──► GitHub ──► Flux source-controller
                            │
        ┌───────────────────┼─────────────────┐
        ▼                   ▼                 ▼
  infra-sources ─► infra-crds ─► infra-controllers ─► infra-config ─► apps
  (HelmRepos)    (Gateway API)  (metallb, traefik,   (Gateway, серт., (по одному Flux
                                cert-manager,        пул MetalLB,     Kustomization
                                longhorn, nfs-csi,   NFS PV медиа)    на приложение)
                                cloudflared)
```

Секреты зашифрованы SOPS+age прямо в git; Flux расшифровывает секретом
`sops-age` (создаётся один раз, императивно — приватный ключ в git не попадает).

## Мобильность нагрузок (ключевое требование)

Нагрузка переезжает между узлами без потери доступа, потому что каждый слой
не привязан к узлу:

1. **Состояние** — Longhorn реплицирует тома на оба узла; при переезде том
   подключается там, где оказался под. Медиа — NFS, монтируется с любого узла.
2. **Маршрутизация** — HTTPRoute → Service → IP пода; Traefik следует за endpoints.
3. **Вход из LAN** — VIP MetalLB переезжает между узлами (L2-анонс).
4. **Публичный вход** — cloudflared соединяется *наружу* с того узла, где
   запущен его под; Cloudflare не знает IP узлов.

## Распределение внешнего состояния

| Где | Что |
|---|---|
| этот репозиторий | всё внутри кластера |
| `nb3_tf` (OpenTofu) | Cloudflare: туннель, CNAME сервисов, настройки зоны |
| Mikrotik | DHCP-резервации, статические DNS-записи split-horizon |
| диски узлов | `/etc/rancher/k3s/config.yaml` (копии в `cluster-setup/`), NFS-экспорт |

## Состав компонентов

| Компонент | Версия | Зачем |
|---|---|---|
| K3s | последний стабильный канал | один бинарник, встроенный etcd, удобен для лаборатории |
| Flux | v2.8 | сводит кластер к состоянию этого репозитория |
| Gateway API CRD | v1.5.1 standard | HTTPRoute в Standard-канале — без экспериментальных CRD |
| Traefik | chart 40.2.0 / v3.7 | провайдер Gateway API, замена встроенного traefik |
| MetalLB | 0.16.1 | L2 VIP для входа из LAN |
| cert-manager | 1.20.2 | wildcard `*.nb3.me` через Cloudflare DNS-01 |
| Longhorn | 1.12.0 | реплицируемое хранилище; StorageClass по умолчанию |
| csi-driver-nfs | 4.13.2 | монтирует NFS-экспорт с медиа |
| cloudflared | 2026.5.2 | исходящий туннель для публичного доступа |
| bjw-s app-template | 4.6.2 | Helm-чарт, на котором построен каждый модуль сервиса |

Ключевые решения:
- **Встроенный etcd вместо SQLite** — второй *server*-узел добавится позже без
  миграции datastore.
- **Traefik через Flux, а не встроенный в k3s** — версия закреплена в git,
  обновления Renovate, провайдер Gateway API включён явно, без HelmChartConfig.
- **app-template для обоих приложений** — поддерживаемого официального чарта
  Paperless нет; единый шаблон делает модули сервисов однотипными.
- **TCPRoute не используется** — всё ещё Experimental-канал; удалённый kubectl
  идёт через TCP-ingress cloudflared.
