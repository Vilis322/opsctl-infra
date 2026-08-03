terraform {
  required_version = ">= 1.6"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = ">= 1.45" # bump to latest if you like; `terraform init` will resolve
    }
  }
}

provider "hcloud" {
  token = var.hcloud_token
}
