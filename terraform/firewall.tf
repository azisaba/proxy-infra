resource "linode_firewall" "proxy" {
  label = "${var.name_prefix}-firewall"

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "allow-ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = var.ssh_allowed_ipv4
    ipv6     = var.ssh_allowed_ipv6
  }

  inbound {
    label    = "allow-simpleproxy"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = tostring(var.proxy_port)
    ipv4     = var.proxy_allowed_ipv4
    ipv6     = var.proxy_allowed_ipv6
  }

  linodes = [for instance in linode_instance.proxy : instance.id]

  lifecycle {
    precondition {
      condition     = length(var.proxy_allowed_ipv4) + length(var.proxy_allowed_ipv6) > 0
      error_message = "At least one proxy source CIDR must be supplied through proxy_allowed_ipv4 or proxy_allowed_ipv6."
    }
  }
}
