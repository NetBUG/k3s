# 08 — Мониторинг: аппаратные метрики с VictoriaMetrics

> Этап M8. Результат: стек VictoriaMetrics в кластере, Grafana на
> `grafana.nb3.me` (только LAN) и реальные температура/CPU/RAM с физических
> хостов, а не только с виртуалок.

## Почему именно «голое железо»

Узлы k3s — это **гостевые** KVM-машины; гипервизор не пробрасывает датчики
температуры хоста в VM, поэтому экспортёр внутри кластера отдаёт CPU/RAM, но
**не температуру**. Реальные температуры даёт `node-exporter`, запущенный на
физических машинах. Два пути сбора, один бэкенд:

| Цель | Экспортёр | Температура? |
|---|---|---|
| узлы k8s (node1, node2…) | DaemonSet из чарта | нет (гость) |
| 192.168.0.237 / .162 (KVM-хосты, amd64) | systemd `node-exporter` | да — `coretemp`/`k10temp` |
| 192.168.0.69 (ARM-плата) | systemd `node-exporter` | да — `thermal_zone` |
| 192.168.0.92 (Linux NAS) | systemd `node-exporter` | да — `hwmon`/`thermal` |

Бэкенд — `victoria-metrics-k8s-stack` (vmsingle + vmagent + Grafana +
kube-state-metrics + node-exporter + vmalert + alertmanager) — примерно в 5–10
раз экономнее по RAM, чем kube-prometheus-stack, что важно на узле с 2 ГиБ.

## 1. Задать пароль администратора Grafana (SOPS)

```bash
# поменяйте пароль, затем зашифруйте на месте ключом age кластера:
$EDITOR infrastructure/controllers/monitoring/grafana-admin.sops.yaml
sops --encrypt --in-place infrastructure/controllers/monitoring/grafana-admin.sops.yaml
```

`.sops.yaml` уже ловит `*.sops.yaml` и шифрует `data/stringData`; Kustomization
`infra-controllers` расшифровывает секрет при применении. **Не коммитьте
открытый текст.**

## 2. Push + reconcile

```bash
git add infrastructure/sources/victoria-metrics.yaml \
        infrastructure/controllers/monitoring infrastructure/config/monitoring \
        infrastructure/{sources,controllers,config}/kustomization.yaml
git commit -m "Add VictoriaMetrics monitoring stack" && git push

flux reconcile source git flux-system
flux reconcile kustomization infra-controllers --with-source
flux reconcile kustomization infra-config --with-source
flux get helmreleases -n monitoring          # vm-stack -> Ready
kubectl -n monitoring get pods               # vmsingle/vmagent/grafana/ksm/node-exporter/vmalert/alertmanager Running
```

> CRD: чарт поставляет CRD оператора VM как обычные манифесты
> (`crds.plain: true`), а HelmRelease использует `crds: CreateReplace`. Если
> Helm когда-нибудь упадёт на размере CRD — запасной вариант: вынести CRD
> оператора в `infrastructure/crds/` (как с Gateway API) и отключить создание
> CRD в чарте.

## 3. Установить node-exporter на физические хосты

Скопируйте скрипт на каждый хост и запустите (идемпотентно; сам определяет
архитектуру/дистрибутив):

```bash
scp scripts/install-node-exporter.sh user@192.168.0.237:/tmp/
ssh user@192.168.0.237 'sudo bash /tmp/install-node-exporter.sh'
# повторить для .162, .69, .92
```

Скрипт ставит `node-exporter` (+ `lm-sensors` на x86), грузит `coretemp`/`k10temp`,
включает systemd-сервис на `:9100` и печатает подсказку по фаерволу — разрешите
`tcp/9100` из `192.168.0.0/24`, если на хосте есть ufw/firewalld.

Добавлять/убирать хосты позже — в файле
`infrastructure/config/monitoring/vmstaticscrape-baremetal.yaml`.

## 4. Проверка

```bash
# vmagent видит все четыре цели на «голом железе» как UP:
kubectl -n monitoring port-forward svc/vmagent-vm-stack 8429 &
curl -s localhost:8429/targets | grep baremetal-node
```

Откройте `https://grafana.nb3.me` в LAN, войдите, откройте **Node Exporter
Full**: по каждому хосту видны температура/CPU/RAM. Узел кластера корректно не
показывает температуру. Запросите `node_hwmon_temp_celsius` /
`node_thermal_zone_temp` в Explore — должны быть ненулевые значения с
`192.168.0.237/.162/.69/.92`.

Grafana доступна **только в LAN**: резолвится через split-horizon DNS на VIP
MetalLB и не имеет ingress в туннеле Cloudflare, поэтому из интернета недоступна.

## 5. Алертинг (на будущее)

`defaultRules` + `infrastructure/config/monitoring/vmrule-hardware.yaml`
(высокая температура, узел недоступен, высокая память) сразу загружаются в
vmalert и видны в UI. Alertmanager пока шлёт в no-op receiver — подключите
реальный канал (Telegram/email/Slack), добавив SOPS-секрет и указав на него в
`alertmanager.config`.

## Масштабирование на node2

Делать ничего не нужно: node-exporter — это DaemonSet (сам появится на node2), а
service discovery vmagent автоматически подхватит новый узел. По желанию поднимите
PVC для vmsingle/Grafana до 2 реплик Longhorn после стабилизации node2.
