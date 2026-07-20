resource "linode_nodebalancer" "proxy" {
  count = var.enable_nodebalancer ? 1 : 0

  label  = "${var.name_prefix}-lb"
  region = var.region
  tags   = local.common_tags
}

resource "linode_nodebalancer_config" "proxy" {
  count = var.enable_nodebalancer ? 1 : 0

  nodebalancer_id = linode_nodebalancer.proxy[0].id
  port            = var.proxy_port
  protocol        = "tcp"
  proxy_protocol  = var.nodebalancer_proxy_protocol
  algorithm       = var.nodebalancer_algorithm
  stickiness      = "none"

  check          = "connection"
  check_interval = 10
  check_timeout  = 5
  check_attempts = 3
}

resource "linode_nodebalancer_node" "proxy" {
  count = var.enable_nodebalancer ? var.instance_count : 0

  nodebalancer_id = linode_nodebalancer.proxy[0].id
  config_id       = linode_nodebalancer_config.proxy[0].id
  label           = linode_instance.proxy[count.index].label
  address         = "${linode_instance.proxy[count.index].private_ip_address}:${var.proxy_port}"
  mode            = "accept"
  weight          = 100

  lifecycle {
    replace_triggered_by = [linode_instance.proxy[count.index]]
  }
}

