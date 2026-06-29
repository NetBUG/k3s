# 02 — kubectl access (local LAN + remote)

> Milestone M2. Result: `kubectl` works from the workstation both on the LAN and away from home.

> **⚠️ Post-M9 (doc 09):** the API server is now **sowilo `192.168.0.92`** (was
> node01 `192.168.122.135`); the remote `k3s.nb3.me` tunnel path is unchanged
> (Service-routed). The `cluster-setup/` configs were renamed — see doc 09.

## Local (LAN)

```bash
scp node1:/etc/rancher/k3s/k3s.yaml ~/.kube/homelab.yaml
# Point at the node instead of loopback:
sed -i '' 's#https://127.0.0.1:6443#https://192.168.5.10:6443#' ~/.kube/homelab.yaml
export KUBECONFIG=~/.kube/homelab.yaml
kubectl get nodes
```

The node IP is valid for the API certificate because it is listed in `tls-san`
(`cluster-setup/node1-server-config.yaml`).

## Remote (Cloudflare Tunnel, recommended)

The cluster's shared tunnel (created in `nb3_tf`, see [05](05-public-and-split-horizon.md))
carries a TCP ingress rule `k3s.nb3.me → tcp://kubernetes.default.svc.cluster.local:443`.
Why not the Gateway: `TCPRoute` is still an Experimental Gateway API channel, while
cloudflared TCP ingress is stable; it also survives a node reinstall, unlike host sshd tricks.

Client side:

```bash
# Terminal 1 — local TCP listener through the tunnel:
cloudflared access tcp --hostname k3s.nb3.me --url 127.0.0.1:6443

# kubeconfig copy for remote use: server points at the local listener,
# tls-server-name matches the SAN baked into the API cert.
kubectl --kubeconfig ~/.kube/homelab-remote.yaml config set-cluster default \
  --server=https://127.0.0.1:6443 --tls-server-name=k3s.nb3.me
kubectl --kubeconfig ~/.kube/homelab-remote.yaml get nodes
```

Fallback: plain SSH port-forward over the existing SSH tunnel
(`cloudflared access ssh` + `ssh -L 6443:127.0.0.1:6443 node1`).

Acceptance: `kubectl get nodes` returns the node both on-LAN and off-LAN.

Next: [03 — GitOps & infrastructure](03-gitops-infra.md)
