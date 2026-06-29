# 07 — Второй узел: присоединение, репликация, переживаем drain

> Этап M7. Результат: 2 узла Ready, тома Longhorn с 2 здоровыми репликами,
> приложения переживают drain узла node1.

> **⚠️ Заменено M9 (doc 09).** Позже роли поменялись: **sowilo — server**,
> **node01 — agent**. Упоминаемый ниже `node2-agent-config.yaml` переименован в
> `node01-agent-config.yaml` (а `node1-server-config.yaml` → `sowilo-server-config.yaml`).

## 1. Подготовка и присоединение node2 (agent)

```bash
# на node2:
sudo apt update && sudo apt install -y open-iscsi nfs-common
sudo systemctl enable --now iscsid

sudo mkdir -p /etc/rancher/k3s
sudo cp cluster-setup/node2-agent-config.yaml /etc/rancher/k3s/config.yaml
# заполнить: URL сервера (IP node1) и токен из
#   node1: sudo cat /var/lib/rancher/k3s/server/node-token
curl -sfL https://get.k3s.io | sh -s - agent
```

```bash
kubectl get nodes    # node1 + node2 Ready
```

Agent (не server): при ровно двух узлах etcd из 2 участников *хуже*, чем из 1
(кворум = 2, падение любого узла останавливает control plane). Будущий третий
узел сможет войти как server — встроенный etcd выбран при установке именно
для этого.

## 2. Longhorn: реплики 1 → 2

Поднять в git (`infrastructure/controllers/longhorn/helmrelease.yaml`):

```yaml
    persistence:
      defaultClassReplicaCount: 2
    defaultSettings:
      defaultReplicaCount: 2
```

`git push` + reconcile. **Это влияет только на новые тома** — существующие
мигрировать явно: Longhorn UI → Volume → каждый том → *Update Replicas Count* → 2,
или:

```bash
kubectl -n longhorn-system get volumes.longhorn.io -o name |
  xargs -I{} kubectl -n longhorn-system patch {} --type=merge \
    -p '{"spec":{"numberOfReplicas":2}}'
# наблюдать за ребилдом:
kubectl -n longhorn-system get replicas.longhorn.io
```

Опционально, но рекомендуется до того, как полагаться на 2 реплики: настроить
backup target Longhorn (S3-совместимый — подходит Cloudflare R2).

## 3. Масштабирование публичного входа

`infrastructure/controllers/cloudflared/deployment.yaml`: `replicas: 1 → 2`
(topologySpreadConstraint уже разносит их по узлам). Push.

## 4. Финальный приёмочный тест — мобильность нагрузок

```bash
kubectl drain node1 --ignore-daemonsets --delete-emptydir-data
kubectl get pods -A -o wide               # всё переезжает на node2
curl -v https://paperless.nb3.me          # оба пути продолжают работать
curl -v https://navidrome.nb3.me
kubectl uncordon node1
```

Почему это работает (см. [architecture.ru.md](../architecture.ru.md)):
том Longhorn переподключается на node2 (реплика уже там) · MetalLB переносит
L2-анонс VIP · вторая реплика cloudflared держит туннель · NFS монтируется
с любого узла.

Оговорка: если node1 — одновременно медиа-узел, приложения на NFS (Navidrome)
теряют медиа на время drain — состояние на Longhorn остаётся целым. Это
ожидаемо: диск с медиа — единственная сознательная единая точка отказа.
