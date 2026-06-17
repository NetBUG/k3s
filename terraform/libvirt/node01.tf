# node01 — libvirt domain "UbuntuK3S" on the KVM host (robothost / "nuc2").
# K3s control-plane VM (guest hostname node01, 192.168.122.134).
#
# INVENTORY / REPRODUCIBILITY ONLY — see README.md. NEVER apply a plan that
# would destroy/replace this domain or its disk; it backs a live cluster.
#
# The provider (dmacvicar/libvirt 0.9.x) uses a nested-attribute schema that
# captures the full domain. The resource HCL is machine-generated from the live
# domain via `tofu plan -generate-config-out` (see README) into node01.generated.tf.
# Live definition of record: node01.domain.xml.

import {
  to = libvirt_domain.node01
  id = "e14cf3ca-00b7-4c09-9ca2-bbeef80f84ef"
}
