# Session — Onboarding `sowilo` into k8s (NAS + agent) — обновлено 2026-06-28

> Изначально задача звучала как «переустановить ОС». **Реинсталл НЕ нужен** —
> машина уже на актуальном LTS с живыми сервисами. План переориентирован на
> **in-place**: ввести узлом + мигрировать Immich, остальное погасить.

## Факты о машине (проверено)

- `sowilo` @ **192.168.0.92**, Intel **N3160** (4 ядра Braswell), **15 GiB RAM**,
  **Ubuntu 24.04.4 LTS**, x86_64.
- **SSH**: переведён на штатный **OpenSSH :22** (dropbear на 10023 убран). Доступ
  `ssh netbug@192.168.0.92`. (Алиас `ssh sowilo` всё ещё указывает на 10023 — обновить локальный `~/.ssh/config` на :22.)
- `netbug` в группе `docker` (docker без sudo). **sudo — с паролем.**
- **Остатков k3s НЕТ** (ни бинарей, ни `/etc/rancher`, `/var/lib/rancher`,
  `/var/lib/kubelet`, `/etc/cni`, ни юнитов, ни flannel/cni). Чистить нечего.

## Диски

- **sda** 119 ГБ **SSD**: `/` (116G, ~46G свободно) + `/boot/efi`. Здесь же
  `/media/data` (immich-postgres, navidrome, jellyfin, nextcloud, syncthing).
- **sdb** 7.3 ТБ → mdraid **md0** (ext4) на **`/media/Magic`**, ~2.5 ТБ свободно. Bulk.
- **Longhorn** на этом узле → отдельный подкаталог **`/media/Magic/longhorn`**
  (HDD медленнее, но для мелких реплик мониторинга ок). Резерв места задать.

## Принцип: NAS-сервисы — на хосте, вне k8s

SMB/Avahi оставляем хостовыми (NAS-first). Файлы в поды — через **NFS**
(`csi-driver-nfs`, как `media-nfs-pv.yaml`; если sowilo станет media-узлом —
перенаправить `server` PV на `192.168.0.92`). В k8s выносим только **compute**.

## Инвентарь Docker-compose (`~/compose/...`) и решения

| Проект | Решение |
|---|---|
| **paperless** | уже мигрирован в k3s, **остановлен** ✅ |
| **immich** | **мигрировать в k8s** (детали ниже) — единственная реальная миграция |
| **navidrome** (222M) | **стоп**, данных нет, конфиг в `~/compose/navidrome`; в k3s уже есть (выключен) |
| **jellyfin** (51M) | **стоп**, данных нет, конфиг в `~/compose/jellyfin` |
| **vault** | **пуст и не инициализирован** (`Initialized:false`, raft-db sparse 52K, file-бэкенд пуст) → мигрировать нечего; **остановлен** |
| **syncthing** | пока оставляем на хосте (file-sync, NAS-смежное) |
| **nginx** | локальный реверс-прокси; роль уменьшается по мере переезда — пересмотреть позже |
| **tgmusicbot** | оставляем на Docker (вне scope) |

## Immich — план миграции (без `pg_dump`)

- **Фото**: `UPLOAD_LOCATION=/media/Magic/netbug/Pictures/PhotoArc` + внешняя
  ro-либа `/media/Magic/netbug/syncthing/Photos_Sony` → **hostPath**, под
  **прибит к sowilo** (`nodeAffinity`). Терабайты не копируем.
- **БД**: образ **`tensorchord/pgvecto-rs:pg14-v0.2.0`** (Postgres14 + вектор),
  данные `/media/data/immich/postgres` → **переиспользовать через hostPath тем же
  образом и тем же UID** (каталог `0700`), тоже прибито к sowilo. Без dump/restore.
- redis 6.2.
- **Версия Immich = та же**, что в Docker (схема БД версионная).
- **Порядок:** `docker compose down` Immich (эксклюзивный доступ к данным БД) →
  поднять в k8s. Никогда два Postgres на одном каталоге.
- Манифесты: предпочтительно **bjw-s app-template** (как paperless) при
  hostPath+node-pin; альтернатива — официальный Helm-чарт Immich (**решить**).
- Наружу: `immich.nb3.me` через туннель (своя авторизация Immich; Access — опц.).

## Контекст: правки VPN/DNS (сделаны)

- **sowilo**: убран перехват DNS через WireGuard (`~.`/`DNS=`); резолв идёт через
  LAN `192.168.0.1`. IPv6 наружу не работает + висит мёртвый IPv6-DNS — **оставили
  как есть** (на резолв не влияет, лишь редкое подтормаживание).
- **green (gc.nb3.me)**: путь **A** — клиентам публичный DNS (`1.1.1.1`), резолвер
  на green не держим. Там же отдельный `amnezia-wg-easy` (Docker, **не трогать**).
  Конфликт имени `wg0` (host wg-quick vs контейнер) — интерфейс подняли; durable-фикс
  (по желанию): переименовать системный wg в отдельное имя, напр. `wgmesh`.

## Сеть: node01 за libvirt-NAT (решено 2026-06-28)

node01 — гость на **nuc2 / `robothost` = 192.168.0.162** (libvirt NAT-сеть
`192.168.122.0/24`, gw `.1`). Из LAN node01 напрямую недоступен (только
исходящий NAT + cloudflared-туннели: `ssh-node.nb3.me`, `k3s.nb3.me` для kubectl).

Чтобы sowilo (LAN `192.168.0.92`) зашёл агентом, нужен L3-путь к серверу **и**
рабочий flannel-VXLAN (udp 8472) в обе стороны. Выбран вариант **маршрутизации**
(node01 НЕ трогаем — без рестарта k3s, без смены flannel/SAN):
- **robothost**: `FORWARD ACCEPT` LAN↔libvirt + `POSTROUTING RETURN`
  (не маскарадим `122.0/24→0.0/24`, чтобы node01 сохранял src `.135` для VXLAN).
- **sowilo**: `ip route add 192.168.122.0/24 via 192.168.0.162`.
- sowilo джойнится на `https://192.168.122.135:6443` (SAN уже валиден).
Альтернатива (отклонена): DNAT 6443+8472 + `node-external-ip`/`flannel-external-ip`
на node01 — требует рестарта control-plane.

Персист: sowilo — netplan `99-k3s-libvirt-route.yaml`; robothost — systemd-юнит
`k3s-libvirt-bridge.service` (`After=libvirtd`, идемпотентные `iptables -C||-I`).

## Порядок выполнения

0. ✅ **ВЫПОЛНЕНО (2026-06-28).** sowilo введён агентом (k3s **v1.35.5+k3s1**,
   `node-ip 192.168.0.92`), узел `Ready`, кросс-нодовая pod-сеть проверена
   (DNS через CoreDNS на node01, ClusterIP достижим). node-exporter на `:9100`
   (7 temp-серий), цель `nas` в vmagent `up`. kubectl починен на sowilo для
   netbug (`~/.kube/config`) и root (`/root/.kube/config`), server переписан на
   `192.168.122.135`. `/media/Magic/longhorn` уже существовал.
   Остаток: применить персист сетевых правил (см. выше) — без него ребут рвёт связь.
1. ✅ **ВЫПОЛНЕНО (2026-06-28). Longhorn `replicas=2`.** Пререквизит: на sowilo
   доставлены `open-iscsi`+`nfs-common`, `iscsid` enabled (без него longhorn-manager
   крашился). Реплики Longhorn на sowilo — на **дефолтном `/var/lib/longhorn` (SSD root,
   48 GiB свободно)**; `/media/Magic/longhorn` оставлен в резерв под отдельные крупные PV.
   Дефолты `defaultReplicaCount`/`defaultClassReplicaCount` подняты до 2 в
   `helmrelease.yaml` (коммит `a4a5feb`, Flux ветка `rebuild-2026`). Все 5 существующих
   томов (paperless ×3, vmsingle, grafana) смигрированы патчем `numberOfReplicas:2` →
   2 healthy-реплики, по одной на узел (`replicaSoftAntiAffinity:false`).
   Хвосты `docs/07`: §3 cloudflared `replicas:2` ✅ (в ingress-HA); §4 **drain-тест node01
   пройден (2026-06-28)** — при drain все ворклоады ушли на sowilo, `photos=200`/`paperless=302`
   без сбоев всю дорогу; 2-я coredns Pending (её `DoNotSchedule` не ставит 2-й под при одном
   узле — ожидаемо), после uncordon разнеслась обратно. §2 Longhorn backup target (R2) — TODO (нужны R2-креды).
2. ✅ **ВЫПОЛНЕНО (2026-06-28). Immich → k8s (bjw-s app-template).** Решено в пользу
   app-template (не офиц. чарта) — он сопротивляется hostPath/переиспользованию готовой БД.
   Манифесты `apps/immich/app/*` (коммит `ef54732`): server+ML+redis+postgres, всё прибито
   к sowilo через `nodeSelector`. hostPath: БД `/media/data/immich/postgres` (UID 999),
   фото `/media/Magic/.../PhotoArc`, ro-либа `Photos_Sony`. Postgres-`args` повторяют
   compose-`command` (vectors.so/search_path), entrypoint не перезатёрт. **Immich запинен
   на `v1.132.1`** (была плавающая `release`). ML model-cache на Longhorn.
   Cutover: `docker compose down` immich + **tar-снапшот БД** (`/media/Magic/backups/
   immich-pg-pre-k8s-20260628.tar`) → push → Flux. Итог: 4 пода `Running`, **БД подхватилась
   (21 351 ассет), миграций нет**, server `v1.132.1` listening. Публичный хост — **`photos.nb3.me`**
   (не immich.nb3.me, коммит `c9ab47f`); туннель/DNS — в nb3_tf (apply вручную).

   ⚠️ **Простой во время cutover:** robothost (гипервизор) на ~пару минут пропал из сети →
   вместе с ним node01 (control-plane + cloudflared). К нашим правкам отношения нет
   (маршрут sowilo и манифесты целы). После оживления Flux досошёлся и развернул Immich.
   Урок: для доступа к sowilo при лежачем node01 — **отдельный cloudflared-туннель на sowilo**
   (`sowilo.nb3.me`, ssh_hosts в nb3_tf), не зависящий от in-cluster cloudflared.
   Публикация (2026-06-28): `photos.nb3.me` → HTTP 200, API `v1.132.1` через туннель ✅.
   `sowilo.nb3.me` — SSH через ВЫДЕЛЕННЫЙ туннель (cloudflared-коннектор на самой sowilo,
   `ssh_hosts` в nb3_tf; алиас в `~/.ssh/config`) — работает независимо от кластера ✅.
   При apply в Cloudflare уже существовали записи `photos`/`sowilo` (81053) — удалены
   вручную, пересозданы Terraform. nb3_tf закоммичен (`6c899f7 "Added Immich"`) + запушен.

3. ✅ **ВЫПОЛНЕНО (2026-06-28).** navidrome/jellyfin остановлены на sowilo (Docker).
4. ✅ **ВЫПОЛНЕНО (2026-06-28).** Vault остановлен (был пуст/не инициализирован — мигрировать нечего).

## Grafana 500 + перенос на sowilo (2026-06-28, коммит `6a668b6`)

Жалоба: Grafana регулярно 500 при открытии дашборда. **Причина — не Grafana:**
`vmsingle` (датасорс-бэкенд) был в **CrashLoopBackOff, OOMKilled, 21 рестарт** —
тяжёлые range-запросы «Node Exporter Full» пробивали лимит **512Mi**, датасорс падал → 500.
Фикс: `vmsingle` лимит памяти **512Mi → 2Gi** (sowilo: 15 GiB). Grafana и vmsingle
**прибиты к sowilo** через `nodeSelector` (оба уже мигрировали туда при простое; Longhorn-
реплика данных на sowilo). Проверено: vmsingle r0, тяжёлый запрос 200 за ~33 мс
(порт vmsingle = **8428**, не 8429). Заметка: pin — hard nodeSelector, при падении sowilo
monitoring не переедет на node01 (приемлемо — sowilo стабильнее).

## robothost: перегрев — вероятная причина крашей (2026-06-28)

node01 (гость на robothost) падал 3× за сессию. Метрики vmsingle показали: **robothost
(192.168.0.162) coretemp до 87°C, при этом все 5 ACPI `Fan` cooling-устройств = `cur_state=0`**.
Причина: фирмварь привязала фаны к зоне **`acpitz` (~27°C)**, а у реальной CPU-зоны
**`x86_pkg_temp` — 0 привязок** → step_wise губернатор никогда не крутит фаны от нагрева CPU.
`thermald` уже был active, но эти on/off фаны не драйвит. PWM/RPM-сенсоров нет (фаны on/off, max=1).
Тест: форс `cur_state=1` (+ `acpitz` policy→`user_space`, чтобы губернатор не сбрасывал) →
pkg 64°C → **51–54°C** (фан реально охлаждает).

Durable-фикс (host, НЕ в git): `/usr/local/sbin/cpu-fan-control.sh` + systemd
`cpu-fan-control.service` на robothost — гистерезис по `x86_pkg_temp` (ON≥65°C / OFF≤53°C),
acpitz в user_space. Файлы-исходники — в scratchpad сессии. Оговорка: 87°C обычно
троттлит, а не крашит; под нагрузкой пики могли быть выше → термо-shutdown. Стоит ещё:
BIOS fan-curve (агрессивнее), чистка/паста, снижение нагрузки на robothost.

Также (для мониторинга при падении node01): vmagent/vmalert/alertmanager прибиты к sowilo
(коммит `909851f`) — скрапер успевает записать предкрашевые метрики robothost, а не умирает
вместе с ним. Longhorn off-site backup на R2 — `available=true` (коммит `5fb9ef6`).

## Открытые вопросы / оговорки

- ✅ ЗАКРЫТО. Immich: выбран **bjw-s app-template**; публичный хост `photos.nb3.me`
  с собственной авторизацией Immich (Cloudflare Access не вешали). Миграция завершена.
- HA при падении node01 по-прежнему требует **3-го сервера** для CONTROL-PLANE (вне scope).
- nb3_tf закоммичен (`6c899f7`) + запушен. Первопричина падений robothost — вероятно перегрев (раздел про фаны); фикс применён, наблюдать. Ingress ребалансирован (cloudflared/traefik на обоих узлах).

## Ingress HA (2026-06-28, коммиты `b79b634`, `9151297`)

node01 (libvirt-гость) дважды падал за час → весь публичный путь (общий cloudflared
+ Traefik, оба на node01) отдавал **1033**, хотя бэкенды (Immich) на sowilo. Разнесли
data-path по двум узлам, чтобы ingress переживал падение node01 (control-plane всё равно
одиночный на node01):
- **cloudflared** `replicas:2` (topologySpread уже был) — 2 коннектора у edge (по 4 соед.).
- **Traefik** `replicas:2` + soft podAntiAffinity по hostname (правка в helmrelease).
- **CoreDNS** `replicas:2` — **императивно** `kubectl scale` (не через Flux: k3s-addon,
  бандл-манифест без `replicas`, поле не его → scale durable; частичный Deployment в Flux
  валит dry-run на immutable selector). topologySpread `DoNotSchedule` сам шлёт 2-й под на sowilo.
- VIP MetalLB не трогали — путь туннеля идёт через ClusterIP Traefik, не через VIP.
Проверено: все три по 2 пода на node01+sowilo, оба cloudflared `/ready=200`, traefik
endpoints ready на обоих, `photos.nb3.me` → 200. Живой drain-тест node01 — опц.
- vmsingle — одиночный (переедет с краткой паузой). Для homelab ок.
- N3160 слаб, но 15 GiB RAM выручают; держать резерв ресурсов под хост-сервисы.
