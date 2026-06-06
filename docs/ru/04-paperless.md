# 04 — Первый сервис: Paperless-ngx

> Этап M4. Результат: `https://paperless.nb3.me` доступен из LAN с валидным
> сертификатом. Это обкатка шаблона **модуля сервиса**.

## Анатомия модуля (`apps/paperless/`)

```
ks.yaml                Flux Kustomization → ./apps/paperless/app (SOPS, dependsOn infra)
app/namespace.yaml     namespace `paperless`
app/pvc.yaml           3 PVC Longhorn: data (SQLite+индекс), media, consume
app/helmrelease.yaml   bjw-s app-template: контроллеры paperless + redis
app/httproute.yaml     paperless.nb3.me → сервис :8000 на общем Gateway
app/secret.sops.yaml   PAPERLESS_SECRET_KEY + учётные данные администратора
```

Замечания по дизайну:
- **app-template** вместо специализированного чарта — поддерживаемого
  официального чарта Paperless нет; один чарт делает все модули однотипными.
- **SQLite + Longhorn** вместо PostgreSQL — однопользовательская лаборатория;
  на один stateful-компонент меньше. Файл БД лежит на реплицируемом томе `data`.
- **Redis без персистентности** — чистый брокер задач, очередь пересоберётся.

## Развёртывание

```bash
# сначала секрет:
cd apps/paperless/app
cp secret.sops.yaml.example secret.sops.yaml   # заполнить значения
sops -e -i secret.sops.yaml                    # раскомментировать в kustomization.yaml
git add -A && git commit -m "Add paperless" && git push
flux reconcile ks apps --with-source
```

Доступ из LAN до этапа 05: уже сейчас добавить статическую DNS-запись на
Mikrotik `paperless.nb3.me → 192.168.5.200` (публичный путь — в [05](05-public-and-split-horizon.md)).

## Проверка

```bash
flux get ks paperless                       # Ready
kubectl -n paperless get pods,pvc           # Running; PVC Bound (longhorn)
kubectl -n paperless get httproute          # Accepted gateway'ем traefik/homelab
curl -v https://paperless.nb3.me            # 200/302, wildcard-сертификат LE
```

Критерий приёмки: страница входа открывается по HTTPS из LAN; загрузка
документа запускает OCR.

Далее: [05 — Публичный доступ и split-horizon](05-public-and-split-horizon.md)
