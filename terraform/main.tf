locals {
  common_tags                  = ["simpleproxy", "terraform"]
  nodebalancer_backend_ipv4    = ["192.168.255.0/24"]
  nodebalancer_ports           = sort(distinct([tostring(var.proxy_port), "25566", "25567"]))
  effective_proxy_allowed_ipv4 = var.enable_nodebalancer ? local.nodebalancer_backend_ipv4 : var.proxy_allowed_ipv4
  effective_proxy_allowed_ipv6 = var.enable_nodebalancer ? [] : var.proxy_allowed_ipv6
}

resource "linode_sshkey" "admin" {
  label   = "${var.name_prefix}-admin"
  ssh_key = trimspace(var.ssh_public_key)
}

resource "linode_instance" "proxy" {
  count = var.instance_count

  label  = format("%s-%02d", var.name_prefix, count.index + 1)
  region = var.region
  type   = var.instance_type
  image  = var.image

  authorized_keys = [linode_sshkey.admin.ssh_key]
  private_ip      = true
  booted          = true
  tags            = local.common_tags

  lifecycle {
    precondition {
      condition     = length(var.ssh_allowed_ipv4) + length(var.ssh_allowed_ipv6) > 0
      error_message = "At least one management CIDR must be supplied through ssh_allowed_ipv4 or ssh_allowed_ipv6."
    }
  }
}
