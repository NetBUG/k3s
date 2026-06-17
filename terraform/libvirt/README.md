# node01 libvirt inventory (OpenTofu)

Captures the KVM domain that runs the K3s control-plane node (`node01`,
guest IP `192.168.122.134`) as code, for **inventory / reproducibility**.
The domain is hand-created; this config adopts it so its shape is documented
and reviewable in git. It is **not** used to manage the VM's lifecycle.

- **Host:** `robothost` / "nuc2" (`192.168.0.162`), libvirt `qemu:///system`.
- **Domain:** `UbuntuK3S` (UUID `e14cf3ca-00b7-4c09-9ca2-bbeef80f84ef`).
- **Live definition of record:** [`node01.domain.xml`](node01.domain.xml)
  (`virsh dumpxml UbuntuK3S`). Re-capture it if you change the VM by hand.

## ⚠️ Read before running anything

`tofu apply` regenerates the domain XML from `node01.tf`. The
`dmacvicar/libvirt` provider does not represent every libvirt auto-added device
(rng, memballoon, pcie-root-port tree, video model, usb tablet, serial/console),
so a `plan` will likely show **cosmetic in-place diffs**. That is fine for
inventory. **Never apply a plan that destroys or replaces the domain or its
disk** — node01 backs a live cluster with stateful data (paperless on Longhorn).
Treat this as read-only: run `init`/`import`/`plan`, not `apply`.

## Prerequisites

- `tofu`, and the libvirt client library locally (macOS: `brew install libvirt`).
- SSH access to the host as `netbug` (in the host `libvirt` group → `qemu:///system`
  is readable without sudo). Host key must be trusted in `~/.ssh/known_hosts`.

## Import (one-time)

```bash
cd terraform/libvirt
tofu init
# Adopt the existing domain by UUID:
tofu import libvirt_domain.node01 e14cf3ca-00b7-4c09-9ca2-bbeef80f84ef
tofu plan        # expect: 0 to add, 0 to destroy; only cosmetic in-place diffs
```

State is local (`terraform.tfstate`, git-ignored). If you want a shared backend
later, add one — but keep it separate from `nb3_tf` (Cloudflare) state.
