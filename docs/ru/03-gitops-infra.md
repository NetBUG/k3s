# 03 — Запуск GitOps и слой инфраструктуры

> Этап M3. Результат: Flux сводит кластер к этому репозиторию; Gateway,
> wildcard-сертификат, VIP, Longhorn — всё зелёное. Обоснования — в
> [architecture.ru.md](../architecture.ru.md).

## 1. Bootstrap Flux

```bash
flux check --pre
flux bootstrap github \
  --owner=netbug --repository=k3s \
  --branch=rebuild-2026 --path=clusters/homelab --personal
```

Команда коммитит `clusters/homelab/flux-system/` и начинает реконсиляцию всего
в `clusters/homelab/` — включая `infrastructure.yaml` и `apps.yaml`.

## 2. Ключ age для SOPS (один раз, императивно)

```bash
age-keygen -o age.agekey                  # НИКОГДА не коммитить этот файл
kubectl -n flux-system create secret generic sops-age \
  --from-file=age.agekey=age.agekey
# ПУБЛИЧНЫЙ ключ (age1...) вписать в .sops.yaml и закоммитить.
```

## 3. Какие секреты заполнить

| Секрет | Где | Как |
|---|---|---|
| Токен Cloudflare DNS (cert-manager) | `infrastructure/config/cf-api-token.sops.yaml` | скопировать из `.example`, заполнить, `sops -e -i`, раскомментировать в kustomization |
| Токен туннеля (cloudflared) | `infrastructure/controllers/cloudflared/secret.sops.yaml` | из `nb3_tf`: `tofu output -raw k8s_tunnel_token` (см. [05](05-public-and-split-horizon.md)) |

## 4. Порядок реконсиляции

`infra-sources → infra-crds → infra-controllers → infra-config → apps`
(задан через `dependsOn` в `clusters/homelab/infrastructure.yaml`).
Пул MetalLB и ClusterIssuer лежат в `infra-config`, потому что им нужны CRD
из слоя контроллеров.

## 5. Проверка

```bash
flux get kustomizations          # все Ready=True
kubectl get gatewayclass,gateway -A         # класс traefik; Gateway homelab Programmed
kubectl -n traefik get certificate          # wildcard-nb3-me Ready
kubectl -n traefik get svc traefik          # EXTERNAL-IP = VIP MetalLB
kubectl get storageclass                    # longhorn (default)
```

Диагностика: `flux logs --level=error -A`, `flux reconcile ks <name> --with-source`.

Далее: [04 — Paperless](04-paperless.md)
