variable "region" {
  description = "Linode region shared by the instances and optional NodeBalancer."
  type        = string
}

variable "instance_count" {
  description = "Number of SimpleProxy instances."
  type        = number
  default     = 10

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 100 && floor(var.instance_count) == var.instance_count
    error_message = "instance_count must be an integer between 1 and 100."
  }
}

variable "instance_type" {
  description = "Linode plan. g6-nanode-1 is Nanode 1 GB."
  type        = string
  default     = "g6-nanode-1"
}

variable "image" {
  description = "Image used for every proxy instance."
  type        = string
  default     = "linode/debian12"
}

variable "name_prefix" {
  description = "Prefix used for Linode labels and related resources."
  type        = string
  default     = "simpleproxy"

  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.name_prefix))
    error_message = "name_prefix may contain lowercase letters, digits, and hyphens only."
  }
}

variable "ssh_public_key" {
  description = "Initial SSH public key installed for root and registered in the Linode account."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^(ssh-|ecdsa-|sk-)", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must be an OpenSSH public key."
  }
}

variable "ssh_allowed_ipv4" {
  description = "IPv4 CIDRs allowed to connect to SSH. Keep this limited to the management host or VPN."
  type        = list(string)
  default     = []
}

variable "ssh_allowed_ipv6" {
  description = "IPv6 CIDRs allowed to connect to SSH."
  type        = list(string)
  default     = []
}

variable "proxy_port" {
  description = "TCP port served by SimpleProxy and the optional NodeBalancer."
  type        = number
  default     = 25565

  validation {
    condition     = var.proxy_port >= 1 && var.proxy_port <= 65535
    error_message = "proxy_port must be between 1 and 65535."
  }
}

variable "proxy_allowed_ipv4" {
  description = "IPv4 CIDRs allowed to reach SimpleProxy. Include 192.168.128.0/17 when using a legacy private-IP NodeBalancer."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "proxy_allowed_ipv6" {
  description = "IPv6 CIDRs allowed to reach SimpleProxy."
  type        = list(string)
  default     = ["::/0"]
}

variable "enable_nodebalancer" {
  description = "Create a regional TCP NodeBalancer in front of all proxy instances."
  type        = bool
  default     = false
}

variable "nodebalancer_algorithm" {
  description = "NodeBalancer routing algorithm. leastconn is suitable for long-lived Minecraft connections."
  type        = string
  default     = "leastconn"

  validation {
    condition     = contains(["roundrobin", "leastconn", "source"], var.nodebalancer_algorithm)
    error_message = "nodebalancer_algorithm must be roundrobin, leastconn, or source."
  }
}

variable "nodebalancer_proxy_protocol" {
  description = "Proxy Protocol version sent to SimpleProxy. Match this with config.yml."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "v1", "v2"], var.nodebalancer_proxy_protocol)
    error_message = "nodebalancer_proxy_protocol must be none, v1, or v2."
  }
}

