# 09 — Перенос control-plane на sowilo (node01 → agent)

> Milestone M9 — **ВЫПОЛНЕНО (2026-06-29).** Результат: **sowilo — k3s server**
> (control-plane + embedded etcd), **node01 — обычный agent** (сейчас закордонен —
> см. заметку про диск ниже). Control-plane больше не живёт на ненадёжном госте
> `robothost`, поэтому падение node01/robothost стоит лишь агента — не API.
>
> **Фактически применён метод Path 1 — snapshot-restore.** sowilo поднят *чистым
> одночленным* сервером, восстановленным из снапшота etcd node01. Изначально
> планировавшийся Path 2 (онлайн-промоушн через окно 2-членного etcd) **отброшен на
> пред-полёте**: robothost оказался в активном краш-лупе из-за **умирающего NVMe**
> (см. «Почему Path 1»), а краш node01 внутри окна кворума-2 остановил бы
> control-plane.

## Зачем

node01 — гость libvirt на `robothost`. Он был **одновременно** единственным
control-plane **и** половиной ingress, поэтому любой сбой robothost ронял API
(и `kubectl`, Flux, алертинг). sowilo — стабильный LAN-хост с 15 GiB RAM, где уже
лежат данные и нагрузка. Перенос control-plane туда — крупнейший выигрыш по
стабильности до появления 3-го сервера.

Control-plane в любом случае остаётся **одночленным** (HA требует 3-го server,
M-future) — мы лишь переносим его на надёжный узел.

## Почему Path 1 (а не планировавшийся Path 2)

Пред-полёт 2026-06-29 показал, что robothost **падает примерно раз в час** (5
загрузок за день, одна — посреди пред-полёта) и в логе ядра **`critical medium
error, dev nvme0n1` ×152**. nvme0n1 — **единственный** диск, на котором и ОС
robothost, и образ ВМ node01. Фикс фана из прошлой сессии работал (`x86_pkg_temp
60°C`, `cpu-fan-control.service` active), так что краши — **отказ диска**, не
перегрев.

Path 2 проходит через 2-членный embedded etcd (кворум 2): если node01 упадёт в
этом окне — а он упадёт из-за диска — control-plane встанет. Path 1 не зависит от
живости node01 и сразу переносит etcd на здоровый диск sowilo. (Исходное описание
Path 2 сохранено в истории git.)

## Что изменилось, а что нет

API переехал с **`192.168.122.135`** (node01, libvirt NAT) на **`192.168.0.92`**
(sowilo, LAN). Обновлено: SAN сертификата и закреплённые kubeconfig'и.
**Без изменений:** состояние кластера (живёт в etcd, восстановлено из снапшота),
in-cluster `cloudflared` для `k3s.nb3.me` (ходит в `kubernetes.default.svc` —
Service, не зависит от сервера, поэтому kubectl с ноута не прерывался), Flux/GitOps,
данные Longhorn и **вся сетевая обвязка** — маршрут sowilo `192.168.122.0/24 via
192.168.0.162` и правила FORWARD/POSTROUTING на robothost остались; поменялись лишь
роли server/agent.

> **Токен — ключевой элемент.** k3s хранит CA кластера + ключи service-account как
> *bootstrap-данные внутри etcd*, зашифрованные токеном кластера. Восстановление
> снапшота на sowilo работает только если sowilo использует **исходный токен**
> node01 — при несовпадении снапшот непригоден. После restore `node-token` sowilo
> вышел **идентичным** node01, подтвердив, что CA сохранён (поэтому существующие
> kubeconfig'и/сертификаты агента остались валидны; node01 вернулся с той же строкой
> токена).

## Пред-полёт (сделано первым, всё снято с умирающего диска)

```bash
# Снапшот, стянут node01 -> sowilo по СТАБИЛЬНОМУ LAN/libvirt-маршруту (не через
# шаткий cloudflared-туннель), sha256 сверен на каждом хопе; 2-я копия на ноут.
ssh ssh-node.nb3.me 'sudo k3s etcd-snapshot save --name pre-m9-final'
# сделать читаемым, затем с sowilo: scp netbug@192.168.122.135:/tmp/... ~/m9/

# Токен кластера (расшифровывает восстановленный bootstrap/CA) — ОБЯЗАТЕЛЕН:
ssh ssh-node.nb3.me 'sudo cat /var/lib/rancher/k3s/server/token'   # K10...::server:...

# База для приёмки: 2 узла, 13 ns, 7 PV, 61 pod.
```

## Шаг 1 — заморозить node01 (старт окна простоя)

```bash
ssh ssh-node.nb3.me 'sudo systemctl stop k3s && sudo systemctl disable k3s'
# API down. node01 лишь ОСТАНОВЛЕН, не снесён — откат = `systemctl enable --now k3s`.
```

## Шаг 2 — поднять sowilo чистым сервером, восстановленным из снапшота

Сделай **server**-`config.yaml` sowilo (`cluster-init: true`, **токен node01**,
`node-ip: 192.168.0.92`, `tls-san` вкл. `192.168.0.92` + `k3s.nb3.me` + `127.0.0.1`,
disable traefik/servicelb/local-storage, `flannel-backend: vxlan`). Затем:

```bash
# на sowilo:
sudo /usr/local/bin/k3s-agent-uninstall.sh
sudo mkdir -p /etc/rancher/k3s && sudo cp sowilo-server-config.yaml /etc/rancher/k3s/config.yaml

# КРИТИЧНО: ставим с SKIP_START, чтобы k3s НЕ сгенерировал свежий CA до restore
# (свежий CA конфликтует с CA из снапшота). Та же версия.
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION=v1.35.5+k3s1 INSTALL_K3S_SKIP_START=true sh -s - server

# Первая операция с etcd — restore (токен берётся из config.yaml):
sudo k3s server --cluster-reset --cluster-reset-restore-path=/path/pre-m9-final.db
#   -> "kvstore restored", "Updating bootstrap data on disk from datastore"
#      (CA из снапшота становится авторитетным; свежий tls-каталог бэкапится),
#      "Managed etcd cluster membership has been reset, restart without --cluster-reset".
sudo systemctl start k3s
```

> agent-uninstall стирает image store containerd, поэтому **все образы качаются
> заново** на sowilo (медленно на N3160). Жди несколько минут массового
> `ContainerCreating`, прежде чем всё осядет.

## Шаг 3 — проверка (приёмка #1)

```bash
# Локально на sowilo (туннель может переподключаться): sudo k3s kubectl get nodes
#   -> только sowilo, ROLES control-plane,etcd. Старый объект node01 авто-удалён
#      (его etcd-член вычищен cluster-reset).
# etcd одночленный: в журнале восстановленный peer https://192.168.0.92:2380.
# Объекты целы vs база: 13 ns / 7 PV / 61 pod. SAN серта включает новый адрес.
curl -sI https://photos.nb3.me                 # 200 — публичный ingress в норме
KUBECONFIG=~/.kube/homelab.yaml kubectl get nodes   # туннель с ноута снова работает
```

## Шаг 4 — вернуть node01 обычным агентом

```bash
# node01 agent config.yaml: server https://192.168.0.92:6443 ; token <тот же> ;
#   node-ip 192.168.122.135
ssh ssh-node.nb3.me 'sudo /usr/local/bin/k3s-uninstall.sh'    # полная чистка старого сервера
# положить agent-конфиг, затем:
curl -sfL https://get.k3s.io | sudo INSTALL_K3S_VERSION=v1.35.5+k3s1 sh -s - agent
# node01 регистрируется как `Ready <none>` за <30с. node01->sowilo:6443 через NAT
# egress; sowilo->поды node01 через неизменный libvirt-маршрут.
```

## Итог / приёмка

```
NAME     STATUS                     ROLES                VERSION
node01   Ready,SchedulingDisabled   <none>               v1.35.5+k3s1   (закордонен — см. ниже)
sowilo   Ready                      control-plane,etcd   v1.35.5+k3s1
```

`photos.nb3.me` = 200, kubectl с ноута через `k3s.nb3.me` работает, 59/61 pod
Running. Свойство «control-plane переживает потерю node01» **доказано на шагах
1–4**: node01 всё это время был полностью остановлен, а sowilo отдавал photos +
kubectl без перерыва — отдельный тест ребутом не нужен.

## Диск node01 портит образы → cordon + точечные исключения

Массовый re-pull образов на node01 после возврата агентом дал **`exec format
error`** на нескольких свежескачанных бинарях (metallb-speaker,
csi-node-driver-registrar, metallb/frr-k8s — побит даже `/bin/sh`). Та же
архитектура (amd64), образы мульти-арч с amd64, другие контейнеры исполняются — то
есть это **порча данных на диске node01** (qcow на умирающем NVMe robothost), не
несовпадение арки. Чистый `crictl rmi` + re-pull починил speaker и csi-nfs-node, но
**frr-k8s воспроизвёл порчу** → не разовый сбой, причина — диск.

Решение (операционное):

- **`kubectl cordon node01`** → `Ready,SchedulingDisabled` (новые ворклоады не
  садятся).
- **Longhorn `nodes.longhorn.io/node01 allowScheduling=false`** (узел + диски) →
  реплики не садятся на битый диск; тома остаются на **1 здоровой реплике на
  sowilo** (статус `degraded`, стабильно — без бесконечного ребилда). Off-site
  backup на R2 — настоящий бэкстоп durability.
- Два **крашлупящих DaemonSet'а** убраны с node01 (здоровые — node-exporter,
  longhorn-manager, metallb-speaker, csi-nfs-node — остаются):
  - `metallb-frr-k8s`: durable через **Flux `postRenderers` kustomize-патч** в
    `infrastructure/controllers/metallb/helmrelease.yaml` (nodeAffinity NotIn node01).
  - `longhorn-csi-plugin`: **live `kubectl patch`** на DaemonSet (nodeAffinity NotIn
    node01). Его *нет* в git, потому что longhorn-manager создаёт этот DaemonSet в
    рантайме (его нет в манифестах чарта, postRenderer не достанет). Применить
    повторно, если longhorn-manager/апгрейд Longhorn откатит.

## Откат

Пред-полётный снапшот лежит на sowilo (`~/m9/pre-m9-final.db`) + на ноуте. Чтобы
вернуть раскладку с node01-сервером: останови k3s на sowilo, а на node01
`k3s server --cluster-reset --cluster-reset-restore-path=<снапшот pre-m9>`, затем
снова добавь sowilo агентом.

## Открытые хвосты

- **Заменить NVMe robothost** — первопричина. До этого node01 лучше держать
  закордоненным/недоверенным для хранилища.
- После ремонта диска: раскордонить node01, включить его Longhorn-диск, убрать блок
  `postRenderers` metallb и live-патч longhorn-csi-plugin, дать Longhorn отстроить
  2-ю реплику.
- HA control-plane по-прежнему требует **3-го сервера** (вне scope).
- При желании убрать `192.168.122.135` из `tls-san` sowilo — node01 больше не сервер.
