# Connects to libvirtd on the KVM host (robothost / "nuc2", 192.168.0.162) over
# SSH. netbug is in the host's libvirt group, so qemu:///system is readable
# without sudo. Requires the libvirt client library on the machine running tofu
# (macOS: `brew install libvirt`).
#
# The provider's Go SSH client does NOT read ~/.ssh/config, so the private key
# and known_hosts must be passed explicitly via URI query params. Override
# var.ssh_keyfile / var.known_hosts for a different workstation.
provider "libvirt" {
  uri = "qemu+ssh://netbug@192.168.0.162/system?keyfile=${var.ssh_keyfile}&known_hosts=${var.known_hosts}&sshauth=privkey"
}

variable "ssh_keyfile" {
  description = "Private key that authenticates to the libvirt host."
  type        = string
  default     = "/Users/netbug/.ssh/id_rsa"
}

variable "known_hosts" {
  description = "known_hosts file containing the libvirt host's key."
  type        = string
  default     = "/Users/netbug/.ssh/known_hosts"
}
