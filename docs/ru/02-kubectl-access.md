# 02 — Доступ kubectl (локально в LAN + удалённо)

> Этап M2. Результат: `kubectl` работает с рабочей машины и в LAN, и вне дома.

> **⚠️ После M9 (doc 09):** API-сервер теперь **sowilo `192.168.0.92`** (был node01
> `192.168.122.135`); путь удалённого туннеля `k3s.nb3.me` не изменился
> (Service-роутинг). Конфиги в `cluster-setup/` переименованы — см. doc 09.

## Локально (LAN)

```bash
scp node1:/etc/rancher/k3s/k3s.yaml ~/.kube/homelab.yaml
# Указать узел вместо loopback:
sed -i '' 's#https://127.0.0.1:6443#https://192.168.5.10:6443#' ~/.kube/homelab.yaml
export KUBECONFIG=~/.kube/homelab.yaml
kubectl get nodes
```

IP узла валиден для сертификата API, потому что указан в `tls-san`
(`cluster-setup/node1-server-config.yaml`).

## Удалённо (Cloudflare Tunnel, рекомендуется)

Общий туннель кластера (создаётся в `nb3_tf`, см. [05](05-public-and-split-horizon.md))
содержит TCP-правило `k3s.nb3.me → tcp://kubernetes.default.svc.cluster.local:443`.
Почему не через Gateway: `TCPRoute` всё ещё в Experimental-канале Gateway API,
а TCP-ingress cloudflared стабилен; к тому же он переживает переустановку узла,
в отличие от трюков с sshd на хосте.

На стороне клиента:

```bash
# Терминал 1 — локальный TCP-листенер через туннель:
cloudflared access tcp --hostname k3s.nb3.me --url 127.0.0.1:6443

# Копия kubeconfig для удалённой работы: server указывает на локальный листенер,
# tls-server-name соответствует SAN, зашитому в сертификат API.
kubectl --kubeconfig ~/.kube/homelab-remote.yaml config set-cluster default \
  --server=https://127.0.0.1:6443 --tls-server-name=k3s.nb3.me
kubectl --kubeconfig ~/.kube/homelab-remote.yaml get nodes
```

Запасной вариант: обычный SSH port-forward через существующий SSH-туннель
(`cloudflared access ssh` + `ssh -L 6443:127.0.0.1:6443 node1`).

Критерий приёмки: `kubectl get nodes` отвечает и в LAN, и вне её.

Далее: [03 — GitOps и инфраструктура](03-gitops-infra.md)
