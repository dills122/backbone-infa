variable "do_token" {
  description = "DigitalOcean Api Token"
}
variable "ssh_key_fingerprint" {
  description = "Fingerprint of the public ssh key stored on DigitalOcean"
}
variable "region" {
  description = "DigitalOcean region"
  default     = "nyc3"
}
variable "droplet_image" {
  description = "DigitalOcean droplet image name"
  default     = "docker-20-04"
}
variable "droplet_size" {
  description = "Droplet size for server"
  default     = "s-1vcpu-2gb-amd"
}
variable "ssh_public_key_path" {
  description = "Local public ssh key path"
  default     = "~/.ssh/id_ed25519.pub"
}
variable "ssh_public_key" {
  description = "Local public ssh key"
  default     = "default"
}
variable "umami_subdomain" {
  type    = string
  default = "umami"
}
variable "domain_name" {
  type = string
}
