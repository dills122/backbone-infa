# Updated: Defined input variables for the streamlined single-droplet Terraform deployment.
variable "do_token" {
  description = "DigitalOcean API token with write access."
  type        = string
  sensitive   = true
}

variable "ssh_key_fingerprint" {
  description = "Optional fingerprint of an SSH key already uploaded to DigitalOcean. If empty, Terraform can create a key from ssh_public_key."
  type        = string
  default     = ""
}

variable "ssh_public_key_path" {
  description = "Path to the local SSH public key to authorize on the droplet when ssh_public_key is not provided."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "ssh_public_key" {
  description = "Optional raw SSH public key content; leave empty to read from ssh_public_key_path."
  type        = string
  default     = ""
}

variable "manage_ssh_key_in_digitalocean" {
  description = "When true and ssh_key_fingerprint is empty, create a DigitalOcean SSH key from ssh_public_key/ssh_public_key_path."
  type        = bool
  default     = true
}

variable "region" {
  description = "DigitalOcean region slug."
  type        = string
  default     = "nyc3"
}

variable "droplet_size" {
  description = "Droplet size slug (defaults to the cost-efficient s-1vcpu-1gb)."
  type        = string
  default     = "s-1vcpu-1gb"
}

variable "droplet_image" {
  description = "Droplet base image slug."
  type        = string
  default     = "ubuntu-24-04-x64"
}

variable "droplet_name" {
  description = "Name assigned to the backbone droplet."
  type        = string
  default     = "backbone-server-1"
}

variable "enable_backups" {
  description = "Enable DigitalOcean-managed backups on the droplet."
  type        = bool
  default     = false
}

variable "extra_tags" {
  description = "Optional additional tags applied to the droplet."
  type        = list(string)
  default     = []
}

variable "repo_url" {
  description = "Git repository URL to clone onto the droplet for runtime assets."
  type        = string
  default     = "https://github.com/dills122/backbone-infa.git"
}

variable "caddy_admin_email" {
  description = "Email address used by Caddy for ACME account registration."
  type        = string
  default     = ""
}

variable "timezone" {
  description = "System timezone to apply on the droplet."
  type        = string
  default     = "UTC"
}

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed to SSH to the droplet (port 22)."
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}
