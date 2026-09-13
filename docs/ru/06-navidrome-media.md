# 06 — Вторая нагрузка: Navidrome на локальном hostPath

> Веха M6. Результат: `music.nb3.me` отдаёт коллекцию с массива sowilo.
> Показывает вариант модуля сервиса с привязкой к узлу (крупная медиатека)
> и приём миграции «переиспользовать существующий каталог состояния».

## Почему hostPath, а не NFS

Изначально веха предполагала NFS-экспорт и статический PV `csi-driver-nfs`,
чтобы под мог работать на любом узле. Экспорт так и не сделали, а к моменту
реального развёртывания сама предпосылка исчезла:

| Вариант | Вердикт |
|---|---|
| **hostPath + nodeSelector** | ✅ выбран — музыка лежит на `md0` в sowilo и больше нигде, «монтировать с любого узла» было недостижимо изначально |
| NFS-экспорт + статический PV | ❌ экспорт жил бы на sowilo и монтировался бы петлёй подом на sowilo: лишний сервис, лишний хоп, page cache оплачен дважды |
| Скопировать в Longhorn | ❌ 131 ГБ данных, пишущихся один раз, с репликацией |

Мобильность, которую покупает NFS, имеет смысл, только если библиотеку может
отдать *второй* узел. Не может — файлы на одном массиве одной машины. Реально
NFS добавил бы здесь демон, способный отказать независимо от того, что он
обслуживает.

Незаменимая часть — SQLite-база с пользователями, плейлистами, оценками и
счётчиками прослушиваний — остаётся на Longhorn: там у неё реплика на node01 и
возможность уехать в бэкап-таргет R2. Плюс Navidrome сам пишет в этот том
ежедневный консистентный дамп (`ND_BACKUP_*`) — снапшот тома с живым
SQLite-файлом консистентность не гарантирует.

## Раскладка на sowilo

| Путь | Что | Монтируется как |
|---|---|---|
| `/media/Magic/netbug/Music/Library` | библиотека, которую сканирует Navidrome (`md0`, массив 7.3 ТБ) | `/music`, только чтение |
| Longhorn PVC `navidrome-data` (5 ГБ) | БД, кэш обложек, ежедневные дампы | `/data` |
| `/media/data/navidrome` | состояние времён Docker, **только источник для seed** | не монтируется |

Всё, к чему прикасается Navidrome, принадлежит `1000:1000` — как и
`user: 1000:1000` у Docker-контейнера. `fsGroup: 1000` у пода делает свежий
том Longhorn записываемым для этого uid; на hostPath-монтирование он не влияет
никак, но тот и так read-only и с правильным владельцем.

В `/media/Magic/netbug/Music` лежат ещё `_Google` (42 ГБ), `_WIP` (69 ГБ,
владелец root) и одиночные видеофайлы. `Library/` намеренно вынесен в
отдельное поддерево, чтобы сканер видел только то, что нужно.

## 1. Подготовить хост

```bash
ssh sowilo.nb3.me
mkdir -p /media/Magic/netbug/Music/Library
chown 1000:1000 /media/Magic/netbug/Music/Library
```

Монтирование объявлено с `hostPathType: Directory`, поэтому отсутствие пути —
громкое падение пода. Без указания типа kubelet молча создаёт пустой каталог
от root, и Navidrome рапортует об идеально здоровой библиотеке из нуля треков.

## 2. Засеять том состояния базой времён Docker

Старое развёртывание (`~/compose/navidrome/`) оставило в `/media/data/navidrome`
файл `navidrome.db` на 40 МБ, последняя запись — 2026-06-28. Он сохраняет
учётные записи, плейлисты и историю прослушиваний.

**Ограничение по версии:** `latest` на ту дату — это **0.62.0**, а миграции
Navidrome односторонние: более старый бинарник новую схему не откроет. Тег
обязан оставаться `>= 0.62.0`; сейчас это `0.63.2`.

Сеять нужно *до* включения приложения, чтобы свежей базы, которую можно
затереть, вообще не возникало:

```bash
kubectl apply -f apps/navidrome/app/namespace.yaml
kubectl apply -f apps/navidrome/app/pvc.yaml
kubectl apply -f apps/navidrome/seed-job.yaml     # разовый, вне Flux
kubectl -n navidrome wait --for=condition=complete job/navidrome-seed --timeout=5m
kubectl -n navidrome logs job/navidrome-seed      # в выводе должен быть navidrome.db
kubectl -n navidrome delete job navidrome-seed
```

Job отказывается работать, если в `/dst` уже есть `navidrome.db`, — случайный
повторный apply не перезапишет живую базу. `/media/data/navidrome` остаётся
нетронутым на диске, это и есть откат.

Пропустить seed тоже допустимо: Navidrome создаст пустую базу, а пользователя
вы заведёте при первом входе.

### Что пустая библиотека делает с засеянной базой

`Library/` стартует пустым, поэтому первое сканирование не найдёт ни одного из
1574 треков, о которых знает база. `Scanner.PurgeMissing` по умолчанию
`never`, так что строки не удаляются, а попадают в раздел *Missing Files*.
Navidrome опознаёт медиа по пути внутри `/music`: если файлы позже окажутся на
тех же относительных путях, история прицепится обратно сама. Это и есть довод
за то, чтобы наполнять `Library/` содержимым `ARTISTS/`, а не класть туда
`ARTISTS/` подкаталогом.

## 3. Включить приложение

`apps/kustomization.yaml` уже содержит `navidrome/ks.yaml`.

```bash
git push && flux reconcile ks apps --with-source
kubectl -n navidrome get pod,pvc
```

## 4. Публичное и LAN-имя

Сервис отвечает на `music.nb3.me`, а не на `navidrome.nb3.me`: имя старше
миграции в k3s (за ним стоял nginx-vhost на sowilo), и клиенты Subsonic
настроены именно на него.

**Перед первым apply** удалите в панели Cloudflare устаревшую запись
`music.nb3.me`. Это остаток досмиграционной схемы, в состоянии Terraform её
нет, и сегодня она отдаёт `530 / error 1033`, потому что ни одно
ingress-правило туннеля её не заявляет. Переименование управляемой записи
`navidrome` в это имя с ней конфликтует.

```bash
cd ../nb3_tf
export TF_VAR_cloudflare_api_token=... TF_VAR_cloudflare_api_nb3_token=...
tofu plan     # ожидаем: CNAME k8s переименован navidrome -> music и следом
              # ingress-правило туннеля. Никаких изменений в ssh*.
tofu apply
```

### LAN-путь — сейчас не работает ни для одного сервиса

Замерено 2026-09-13: split-horizon на Mikrotik из [05](05-public-and-split-horizon.md)
так и не настроили. `paperless.nb3.me`, `photos.nb3.me` и `music.nb3.me` с
роутера резолвятся в edge-адреса Cloudflare, то есть LAN-клиенты уже сегодня
выходят наружу и возвращаются через туннель.

Статическая запись на VIP MetalLB это не чинит. `192.168.122.200` — адрес в
**libvirt**-подсети: у sowilo там нет интерфейса (только ручной маршрут
`192.168.122.0/24 via 192.168.0.26`, сосед в состоянии `INCOMPLETE`), а
единственный узел, способный ответить на ARP, — node01, и он `NotReady`.
`curl` на VIP *с узла кластера* при этом отвечает всегда: kube-proxy делает
DNAT адреса LoadBalancer локально, так что такая проверка про LAN-клиента не
говорит ничего.

Два выхода, оба не про Navidrome:

```
# A. Затычка, работает сегодня: NodePort Traefik на LAN-адресе sowilo.
/ip dns static add name=music.nb3.me address=192.168.0.92 comment="sowilo NodePort"
#    -> https://music.nb3.me:30289   (валидный wildcard-сертификат, Host и SNI совпадают)
#    Сначала закрепить nodePort в HelmRelease Traefik — 30289 выдан автоматически.

# B. Нормальное решение: перенести пул MetalLB в 192.168.0.0/24, чтобы анонс
#    делал speaker самого sowilo через enp1s0. Чистый :443, без robothost и node01.
#    .200 занят; .201-.215 не ответили — сверить с пулом DHCP.
```

```
/ip dns static remove [find name="navidrome.nb3.me"]
```

## 5. Проверка

```bash
kubectl -n navidrome get pod -o wide            # на sowilo
kubectl -n navidrome exec deploy/navidrome -- ls /music | head
kubectl -n navidrome logs deploy/navidrome | grep -i "scan\|migrat"

curl -sI https://music.nb3.me                   # 200, не 530/404
curl -s https://music.nb3.me/ping               # ping-эндпоинт Subsonic
```

`530 / error 1033` — у туннеля нет ingress-правила для имени (проверьте, что
`tofu apply` отработал); `404` от Traefik — правило есть, но не совпал ни один
HTTPRoute (проверьте hostname в `httproute.yaml`).

## Откат

```bash
# вернуться к базе времён Docker, на месте:
kubectl -n navidrome delete job navidrome-seed --ignore-not-found
flux suspend hr navidrome -n navidrome
kubectl -n navidrome scale deploy navidrome --replicas=0
# пересев: удалить PVC, применить заново pvc.yaml + seed-job.yaml, снять suspend
```

Оригинальный `/media/data/navidrome` кластер не пишет никогда.

Далее: [07 — Второй узел](07-second-node.md)
