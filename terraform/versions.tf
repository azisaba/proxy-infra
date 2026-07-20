terraform {
  required_version = "~> 1.14.0"

  required_providers {
    linode = {
      source  = "linode/linode"
      version = "~> 4.1"
    }
  }
}

provider "linode" {}

