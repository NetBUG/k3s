# 11 — Панель Homarr (home.nb3.me) и Home Assistant за Traefik

> Итог: одно имя панели для LAN и WAN. Анонимный посетитель из WAN видит
> публичную доску, устройства в LAN попадают на LAN-доску, а залогиненный
> пользователь видит всё откуда угодно. Home Assistant подключён к Gateway как
> обычное приложение.

## Как различается запрос

Каждый запрос через туннель Cloudflare несёт заголовок `Cf-Ray`. Cloudflare
добавляет его на краю и добавляет заново, если клиент прислал пустой, поэтому
клиент из WAN убрать его не может. Запросы из LAN приходят на VIP MetalLB без
него. HTTPRoute (`apps/homarr/app/httproute.yaml`) этим пользуется:

| Запрос | Результат |
|---|---|
| `GET /` с `Cf-Ray` (WAN) | главная Homarr: публичная доска, после входа — доска пользователя по умолчанию |
| `GET /` без `Cf-Ray` (LAN) | `302 /boards/lan` |
| любой другой путь | Homarr |

Клиент в LAN, подделавший `Cf-Ray`, лишь получает поведение WAN. Проверено
2026-10-13 временным маршрутом `traefik/whoami`: WAN `X-View: wan`, LAN `lan`,
LAN + поддельный заголовок `wan`, WAN + пустой заголовок всё равно `wan`.

Редирект — единственная часть, знающая о сети. Сам Homarr не умеет доверять
заголовку прокси для входа, поэтому LAN-доска всё равно требует входа, один
раз на устройство (`AUTH_SESSION_EXPIRY_TIME: 365d`).

## Доски (`apps/homarr/panel.yaml`)

Доски, приложения и состав групп описаны в `apps/homarr/panel.yaml` и
применяются скриптом `apps/homarr/sync.py` через API Homarr. В базе Homarr
(том Longhorn `homarr-database`) лежит применённая копия; повторный запуск
пересобирает каждую управляемую доску, поэтому плитки, добавленные на эти доски
в UI, пропадут. Доски и приложения, не названные в файле, не трогаются.

| Доска | Доступ | Группы |
|---|---|---|
| `public` | публичная; домашняя для анонимов | Public: Navidrome, Immich, Seafile |
| `remote` | приватная; доска пользователя по умолчанию | Public; Personal: Paperless; Auxiliary: Grafana, Home Assistant, UniFi Cloud |
| `lan` | приватная; `/` из LAN перенаправляется сюда | Public; Personal: Syncthing, Paperless; Auxiliary: Grafana, Home Assistant, UniFi |

У Syncthing (`http://192.168.1.125:8384`, Docker на sowilo) и консоли UniFi
(`https://192.168.1.1`) нет пути из WAN, поэтому они только на `lan`.
Репозиторий публичный, так что URL облачной консоли UniFi берётся из
окружения, а не из файла:

```bash
cd apps/homarr
export HOMARR_API_KEY=...      # Homarr: Management -> Tools -> API
export UNIFI_CLOUD_URL=https://unifi.ui.com/consoles/...
./sync.py --dry-run            # только чтение, печатает планируемые записи
./sync.py
```

Id секций и плиток выводятся из имён доски/группы/приложения, поэтому повторный
запуск пишет идентичное содержимое. Плитки 2x1 на 12-колоночной базовой
раскладке и 1x1 на 3-колоночной мобильной. Скрипту нужен PyYAML.

Заметки по API: REST-чтения содержимого доски нет; скрипт читает его через
tRPC-маршрут `board.getBoardByName` с тем же заголовком `ApiKey`. Cloudflare
отвергает User-Agent `Python-urllib` по умолчанию (ошибка 1010), поэтому
скрипт шлёт свой. `PATCH /api/boards/{id}/home` требует тело `{}`, хотя в
схеме тела нет.

## 1. Секрет

```bash
cd apps/homarr/app
cp secret.sops.yaml.example secret.sops.yaml   # openssl rand -hex 32
sops -e -i secret.sops.yaml
```

Затем раскомментировать `homarr/ks.yaml` в `apps/kustomization.yaml`. Копию
ключа хранить вне кластера: без него все секреты интеграций в базе придётся
вводить заново.

## 2. Порядок выкатки

1. Push netbug_k3s. Flux создаёт HTTPRoute `homarr` и `home-assistant`;
   ExternalDNS добавляет LAN-записи `home` и `ha` на роутере.
2. `tofu apply` в nb3_tf: имя туннеля `home` + CNAME, и `ha` переключён с
   `http://192.168.1.27:8123` на origin Traefik. Если применить это первым,
   `ha` будет отдавать 404, пока не появится HTTPRoute.
3. Открыть `https://home.nb3.me` из LAN, создать администратора (onboarding),
   создать API-ключ, затем запустить `apps/homarr/sync.py`.

## Home Assistant

HA работает вне кластера (HAOS VM `haos` на cn62). `apps/home-assistant` даёт
ему Service без селектора плюс EndpointSlice на `192.168.1.27:8123` и
HTTPRoute для `ha.nb3.me`. Traefik (как и cloudflared до него) работает на
sowilo, поэтому HA видит тот же адрес источника, что и раньше, и
`trusted_proxies` менять не нужно. Если Traefik когда-нибудь окажется на
node01, добавить исходящий адрес этого узла в `trusted_proxies`.

## Проверка

```bash
dig +short home.nb3.me @192.168.1.1          # 192.168.1.100
dig +short ha.nb3.me @192.168.1.1            # 192.168.1.100
curl -sI https://home.nb3.me/ | grep -i location        # LAN: /boards/lan
curl -sI --resolve home.nb3.me:443:$(dig +short home.nb3.me @1.1.1.1 | head -1) \
  https://home.nb3.me/ | head -1                        # WAN: без редиректа на /boards/lan
curl -s -o /dev/null -w '%{http_code}\n' https://ha.nb3.me/   # 200
```
