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

resource "linode_nodebalancer_config" "proxy_additional" {
  for_each = var.enable_nodebalancer ? local.nodebalancer_additional_ports : toset([])

  nodebalancer_id = linode_nodebalancer.proxy[0].id
  port            = tonumber(each.value)
  protocol        = "tcp"
  proxy_protocol  = var.nodebalancer_proxy_protocol
  algorithm       = var.nodebalancer_algorithm
  stickiness      = "none"

  check          = "connection"
  check_interval = 10
  check_timeout  = 5
  check_attempts = 3
}

resource "linode_nodebalancer_node" "proxy_additional" {
  for_each = var.enable_nodebalancer ? local.nodebalancer_additional_node_pairs : {}

  nodebalancer_id = linode_nodebalancer.proxy[0].id
  config_id       = linode_nodebalancer_config.proxy_additional[each.value.port].id
  label           = linode_instance.proxy[each.value.instance_index].label
  address         = "${linode_instance.proxy[each.value.instance_index].private_ip_address}:${each.value.port}"
  mode            = "accept"
  weight          = 100

  lifecycle {
    replace_triggered_by = [linode_instance.proxy[tonumber(split("-", each.key)[1])]]
  }
}
