output "instance_ids" {
  description = "Linode IDs keyed by label."
  value       = { for instance in linode_instance.proxy : instance.label => instance.id }
}

output "public_ipv4" {
  description = "Public IPv4 addresses keyed by label."
  value       = { for instance in linode_instance.proxy : instance.label => instance.ip_address }
}

output "private_ipv4" {
  description = "Private IPv4 addresses keyed by label."
  value       = { for instance in linode_instance.proxy : instance.label => instance.private_ip_address }
}

output "nodebalancer_ipv4" {
  description = "Public NodeBalancer IPv4 address, or null when disabled."
  value       = var.enable_nodebalancer ? linode_nodebalancer.proxy[0].ipv4 : null
}

output "nodebalancer_hostname" {
  description = "NodeBalancer hostname, or null when disabled."
  value       = var.enable_nodebalancer ? linode_nodebalancer.proxy[0].hostname : null
}

