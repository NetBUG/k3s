# 05 — Публичный доступ (Cloudflare Tunnel) и split-horizon в LAN

> Этап M5. Результат: `paperless.nb3.me` работает одинаково вне LAN
> (Cloudflare edge) и внутри LAN (напрямую на VIP) — один hostname, валидный
> TLS на обоих путях.

## Как сочетаются два пути

См. [architecture.ru.md](../architecture.ru.md#два-пути-доступа-один-hostname).
Ключевое ограничение: у nb3.me включён `always_use_https=on` (нужен
существующему SSH-туннелю — **никогда не менять**), поэтому LAN-путь обязан
терминировать TLS wildcard-сертификатом из этапа 03. Не включать HSTS на
Cloudflare edge, пока оба пути не проверены.

## 1. Terraform (nb3_tf)

Всё уже описано в `k8s_services.tf` + `terraform.tfvars` (map `k8s_services`:
paperless, navidrome, k3s-api). Запуск с токенами из окружения:

```bash
cd ../nb3_tf
export TF_VAR_cloudflare_api_token=... TF_VAR_cloudflare_api_nb3_token=...
tofu plan    # ДОЛЖНЫ быть только создания — ноль изменений в ssh* и настройках зоны
tofu apply
```

Создаётся: туннель `k8s-homelab`, удалённо управляемые ingress-правила
(hostname → `https://traefik.traefik.svc.cluster.local:443` с Host/SNI равными
публичному hostname), проксируемые CNAME → `<tunnel-id>.cfargotunnel.com`.

## 2. Передать токен туннеля в кластер

```bash
tofu output -raw k8s_tunnel_token   # base64-токен для `cloudflared tunnel run`
cd ../Ste30_k3s/netbug_k3s/infrastructure/controllers/cloudflared
kubectl create secret generic tunnel-token -n cloudflared \
  --from-literal=TUNNEL_TOKEN="$(cd ../../../../nb3_tf && tofu output -raw k8s_tunnel_token)" \
  --dry-run=client -o yaml > secret.sops.yaml
sops -e -i secret.sops.yaml         # затем раскомментировать в kustomization.yaml
git add -A && git commit -m "Add tunnel token" && git push
```

cloudflared подключается наружу; проверка: `kubectl -n cloudflared logs deploy/cloudflared`
должен показать 4 зарегистрированных соединения с edge.

## 3. Split-horizon на Mikrotik

```
/ip dns static add name=paperless.nb3.me address=192.168.5.200 comment="k8s VIP"
/ip dns static add name=navidrome.nb3.me address=192.168.5.200 comment="k8s VIP"
```

(По записи на сервис; regexp-wildcard `.*\\.nb3\\.me` зацепил бы и
`ssh-agent.nb3.me`, сломав SSH-туннель — не делать.)

## 4. Проверка обоих путей

```bash
# LAN (резолвится в VIP, сертификат = wildcard Let's Encrypt):
dig +short paperless.nb3.me @192.168.5.1     # -> 192.168.5.200
curl -v https://paperless.nb3.me 2>&1 | grep -E "subject|issuer"

# Публично (принудительный резолв через Cloudflare):
dig +short paperless.nb3.me @1.1.1.1         # -> IP edge Cloudflare
curl -v --resolve paperless.nb3.me:443:$(dig +short paperless.nb3.me @1.1.1.1 | head -1) \
  https://paperless.nb3.me 2>&1 | grep -E "subject|issuer"

# Удалённый kubectl (см. 02): cloudflared access tcp --hostname k3s.nb3.me --url 127.0.0.1:6443

# SSH-туннель обязан продолжать работать:
cloudflared access ssh --hostname ssh-agent.nb3.me
```

Далее: [06 — Navidrome и медиа](06-navidrome-media.md)
