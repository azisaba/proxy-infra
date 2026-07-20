resource "linode_firewall" "proxy" {
  label = "${var.name_prefix}-firewall"

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "allow-ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = length(var.ssh_allowed_ipv4) > 0 ? var.ssh_allowed_ipv4 : null
    ipv6     = length(var.ssh_allowed_ipv6) > 0 ? var.ssh_allowed_ipv6 : null
  }

  inbound {
    label    = "allow-simpleproxy"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = tostring(var.proxy_port)
    ipv4     = length(local.effective_proxy_allowed_ipv4) > 0 ? local.effective_proxy_allowed_ipv4 : null
    ipv6     = length(local.effective_proxy_allowed_ipv6) > 0 ? local.effective_proxy_allowed_ipv6 : null
  }

  linodes = [for instance in linode_instance.proxy : instance.id]

  depends_on = [
    linode_firewall.nodebalancer,
    linode_nodebalancer_node.proxy,
  ]

  lifecycle {
    precondition {
      condition     = length(var.proxy_allowed_ipv4) + length(var.proxy_allowed_ipv6) > 0
      error_message = "At least one public proxy source CIDR must be supplied through proxy_allowed_ipv4 or proxy_allowed_ipv6."
    }
  }
}

resource "linode_firewall" "nodebalancer" {
  count = var.enable_nodebalancer ? 1 : 0

  label = "${var.name_prefix}-nodebalancer-firewall"

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "allow-simpleproxy"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = tostring(var.proxy_port)
    ipv4     = length(var.proxy_allowed_ipv4) > 0 ? var.proxy_allowed_ipv4 : null
    ipv6     = length(var.proxy_allowed_ipv6) > 0 ? var.proxy_allowed_ipv6 : null
  }

  nodebalancers = [linode_nodebalancer.proxy[0].id]

  lifecycle {
    precondition {
      condition     = length(var.proxy_allowed_ipv4) + length(var.proxy_allowed_ipv6) > 0
      error_message = "At least one public proxy source CIDR must be supplied through proxy_allowed_ipv4 or proxy_allowed_ipv6."
    }
  }
}
