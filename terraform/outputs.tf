# Updated: Exposed droplet connection details for quick access after apply.
output "droplet_ip" {
  description = "Public IPv4 address of the backbone droplet."
  value       = digitalocean_droplet.backbone_server_1.ipv4_address
}

output "ssh_command" {
  description = "Convenience SSH command for connecting to the droplet."
  value       = format("ssh ubuntu@%s", digitalocean_droplet.backbone_server_1.ipv4_address)
}

output "docker_host" {
  description = "Docker host environment variable value for remote Compose usage."
  value       = format("ssh://ubuntu@%s", digitalocean_droplet.backbone_server_1.ipv4_address)
}
