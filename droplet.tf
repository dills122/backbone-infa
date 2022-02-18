data "template_file" "userdata" {
  template = file("${path.module}/app.yaml")

  vars = {
    pub_key = var.ssh_public_key != "default" ? var.ssh_public_key : file(var.ssh_public_key_path)
  }
}

# Setup a DO droplet
resource "digitalocean_droplet" "backbone_server_1" {
  image  = var.droplet_image
  name   = "backbone-server-1"
  region = var.region
  size   = var.droplet_size
  ssh_keys = [
    var.ssh_key_fingerprint
  ]
  user_data = data.template_file.userdata.rendered
}

################################################################################
# Create a DNS A records for all the services required                                                                     #
################################################################################
resource "digitalocean_record" "umami-base" {
  domain = "${var.umami_subdomain}.${data.digitalocean_domain.web.name}"
  type   = "A"
  name   = "@"
  value  = digitalocean_droplet.backbone_server_1.ipv4_address
  ttl    = 3600
}
resource "digitalocean_record" "umami-www" {
  domain = "${var.umami_subdomain}.${data.digitalocean_domain.web.name}"
  type   = "A"
  name   = "www"
  value  = digitalocean_droplet.backbone_server_1.ipv4_address
  ttl    = 3600
}

# Output the public IP address of the new droplet
output "public_ip_server" {
  value = digitalocean_droplet.backbone_server_1.ipv4_address
}
