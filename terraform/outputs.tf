# Updated: Exposed droplet connection details for quick access after apply.
output "droplet_ip" {
  description = "Public IPv4 address of the backbone droplet."
  value       = digitalocean_droplet.backbone_server_1.ipv4_address
}

output "ssh_command" {
  description = "Convenience SSH command for initial connection to the droplet."
  value       = format("ssh root@%s", digitalocean_droplet.backbone_server_1.ipv4_address)
}

output "ssh_command_ubuntu" {
  description = "Convenience SSH command after cloud-init/setup creates and configures the ubuntu user."
  value       = format("ssh ubuntu@%s", digitalocean_droplet.backbone_server_1.ipv4_address)
}

output "docker_host" {
  description = "Docker host environment variable value for remote Compose usage."
  value       = format("ssh://root@%s", digitalocean_droplet.backbone_server_1.ipv4_address)
}

output "firewall_id" {
  description = "DigitalOcean firewall ID protecting the droplet."
  value       = digitalocean_firewall.backbone_server_1.id
}

output "effective_ssh_key_fingerprint" {
  description = "SSH key fingerprint used by the droplet."
  value       = local.effective_ssh_keys[0]
}
