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
  effective_ssh_public_key = trimspace(var.ssh_public_key != "" ? var.ssh_public_key : file(pathexpand(var.ssh_public_key_path)))
  default_tags             = ["backbone"]
  effective_ssh_keys = trimspace(var.ssh_key_fingerprint) != "" ? [
    trimspace(var.ssh_key_fingerprint)
    ] : [
    digitalocean_ssh_key.backbone_provisioning[0].fingerprint
  ]
  dns_records = var.manage_dns_records && trimspace(var.domain_name) != "" ? {
    root  = var.root_record_name
    blog  = var.blog_record_name
    umami = var.umami_record_name
    www   = var.www_record_name
  } : {}
}

resource "digitalocean_ssh_key" "backbone_provisioning" {
  count = var.manage_ssh_key_in_digitalocean && trimspace(var.ssh_key_fingerprint) == "" ? 1 : 0

  name       = "${var.droplet_name}-provisioning"
  public_key = local.effective_ssh_public_key
}

resource "digitalocean_droplet" "backbone_server_1" {
  name       = var.droplet_name
  region     = var.region
  size       = var.droplet_size
  image      = var.droplet_image
  backups    = var.enable_backups
  monitoring = true
  tags       = distinct(concat(local.default_tags, var.extra_tags))

  ssh_keys = local.effective_ssh_keys

  user_data = templatefile("${path.module}/../cloud-init.sh", {
    ssh_public_key = local.effective_ssh_public_key
    repo_url       = var.repo_url
    caddy_email    = var.caddy_admin_email
    timezone       = var.timezone
  })
}

resource "digitalocean_firewall" "backbone_server_1" {
  name        = "${var.droplet_name}-firewall"
  droplet_ids = [digitalocean_droplet.backbone_server_1.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = var.ssh_allowed_cidrs
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "443"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "1-65535"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}

resource "digitalocean_record" "backbone_a_records" {
  for_each = local.dns_records

  domain = var.domain_name
  type   = "A"
  name   = each.value
  value  = digitalocean_droplet.backbone_server_1.ipv4_address
  ttl    = var.dns_ttl
}
