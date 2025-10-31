# Updated: Consolidated Terraform config for a single DigitalOcean droplet bootstrapped with Docker and Caddy.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

locals {
  effective_ssh_public_key = trimspace(var.ssh_public_key != "" ? var.ssh_public_key : file(var.ssh_public_key_path))
  default_tags             = ["backbone"]
}

resource "digitalocean_droplet" "backbone_server_1" {
  name       = var.droplet_name
  region     = var.region
  size       = var.droplet_size
  image      = var.droplet_image
  backups    = var.enable_backups
  monitoring = true
  tags       = distinct(concat(local.default_tags, var.extra_tags))

  ssh_keys = [
    var.ssh_key_fingerprint
  ]

  user_data = templatefile("${path.module}/../cloud-init.sh", {
    ssh_public_key = local.effective_ssh_public_key
    repo_url       = var.repo_url
    caddy_email    = var.caddy_admin_email
    timezone       = var.timezone
  })
}
