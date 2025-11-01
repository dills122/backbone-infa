<!-- Updated: Comprehensive repository overview and usage guide after the modernization refactor. -->

# Backbone Infrastructure

Backbone Infrastructure provisions a single DigitalOcean droplet (Ubuntu 24.04) that runs Dockerized services behind Caddy with automatic HTTPS. Terraform manages droplet lifecycle, `cloud-init.sh` bootstraps the host with Docker and repo assets, and Docker Compose provides an extensible platform for personal web services.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Repository Layout](#repository-layout)
3. [Prerequisites](#prerequisites)
4. [Quick Start](#quick-start)
5. [Terraform Workflow](#terraform-workflow)
6. [Cloud-Init Bootstrap](#cloud-init-bootstrap)
7. [Docker & Caddy Stack](#docker--caddy-stack)
8. [Service Onboarding](#service-onboarding)
9. [Environment Variables](#environment-variables)
10. [Optional Profiles & Future Modules](#optional-profiles--future-modules)
11. [Scripts](#scripts)
12. [CI / Automation](#ci--automation)
13. [Troubleshooting](#troubleshooting)
14. [Reference Commands](#reference-commands)
15. [License](#license)

---

## Architecture

- **Terraform (DigitalOcean provider)** manages only the droplet lifecycle. It provisions a single DigitalOcean droplet (`s-1vcpu-1gb` by default, roughly $6/month) and injects our bootstrap script via `user_data`. Override sizes safely through `terraform.tfvars`.
- **Cloud-init** executes `cloud-init.sh` on first boot to install Docker, configure the `ubuntu` user, clone this repo under `/opt/backbone-infa`, and optionally bring the Docker stack online.
- **Docker Compose** orchestrates Caddy as the public entry point plus optional monitoring/backups containers while keeping every application networked internally on the shared `backbone` bridge.
- **Caddy** fully replaces the old Nginx + Certbot stack. It terminates TLS using Let’s Encrypt and routes domains defined by service snippets stored in `docker/sites/`.
- **Templates & scripts** standardize how new services are added without rewriting boilerplate.

---

## Repository Layout

```
terraform/                # DigitalOcean IaC (main.tf, variables, outputs)
docker/
  docker-compose.yml      # Core stack with Caddy + optional profiles
  Caddyfile               # Imports site snippets from docker/sites/
  sites/                  # Per-service Caddy definitions (git-kept empty)
templates/
  service-template/       # Compose + Caddy snippets for new services
scripts/
  add-service.sh          # Helper to scaffold service snippets
services/                 # Generated service snippets (ignored if empty)
cloud-init.sh             # Idempotent droplet bootstrap script
.env.example              # Shared environment file consumed by Compose/Caddy
.github/workflows/        # Terraform formatting & validation workflow
```

---

## Prerequisites

- Terraform 1.5+ (tested with 1.6.6)
- DigitalOcean account with:
  - API token (write scope) available as `TF_VAR_do_token`
  - Uploaded SSH public key (fingerprint exported as `TF_VAR_ssh_key_fingerprint`)
- Local Docker CLI with Compose plugin (for testing or remote management)
- Optional tooling: `shellcheck` (validate bootstrap script), `jq`

---

## Quick Start

1. **Clone the repo** and switch to it.
2. **Copy the example environment file:**
   ```bash
   cp .env.example .env
   ```
   Set at least `CADDY_ADMIN_EMAIL` and any service-specific values you intend to use.
3. **Export Terraform variables** (never commit secrets):
   ```bash
   export TF_VAR_do_token=your_digitalocean_token
   export TF_VAR_ssh_key_fingerprint=aa:bb:cc:dd
   export TF_VAR_caddy_admin_email=ops@example.com   # optional but recommended
   ```
4. **Optional:** Override defaults in `terraform/terraform.tfvars` (or `prod.auto.tfvars`) if you need different sizes/regions. For example:
   ```hcl
   droplet_size = "s-1vcpu-2gb"
   timezone     = "America/Chicago"
   ```
5. **Provision the droplet:**
   ```bash
   terraform -chdir=terraform init
   terraform -chdir=terraform plan -out backbone.tfplan
   terraform -chdir=terraform apply "backbone.tfplan"
   ```
6. **Connect to the droplet** using the Terraform output (`ssh ubuntu@<ip>`).
7. **Start services** if the bootstrap skipped them (e.g., no `.env` yet):
   ```bash
   cd /opt/backbone-infa/docker
   docker compose up -d
   ```

---

## Terraform Workflow

- **Configuration files:** `terraform/main.tf`, `variables.tf`, `outputs.tf`
- Terraform intentionally manages only the droplet lifecycle. Runtime services are handled by Docker Compose once the host is online.
- **Key variables:**
  - `do_token`, `ssh_key_fingerprint` (required)
  - `droplet_size`, `region`, `droplet_name`, `enable_backups`, `timezone`
  - `caddy_admin_email` (passed through to Caddy & cloud-init)
- **Recommended commands:**
  ```bash
  terraform -chdir=terraform fmt
  terraform -chdir=terraform validate
  terraform -chdir=terraform plan -var-file=prod.auto.tfvars
  ```
- **Destroying infrastructure:**
  ```bash
  terraform -chdir=terraform destroy
  ```
- **Outputs:**
  - `droplet_ip` — usable for DNS A records
  - `ssh_command` — copy/paste login
  - `docker_host` — convenient `DOCKER_HOST=ssh://ubuntu@<ip>`

---

## Cloud-Init Bootstrap

`cloud-init.sh` runs once via DigitalOcean user data and is safe to re-run manually. It:

1. Installs apt packages (Docker, git, ufw, prerequisites).
2. Sets the system timezone (`TF_VAR_timezone`, default UTC).
3. Ensures the `ubuntu` user exists, adds your SSH public key, and joins the `docker` group.
4. Enables ufw (allowing OpenSSH, HTTP, HTTPS).
5. Clones or updates this repository in `/opt/backbone-infa`.
6. Writes `/etc/backbone-caddy.env` with the Caddy admin email hint.
7. Invokes `docker compose` if both `docker/docker-compose.yml` and `.env` are present.
8. Verifies Caddy is running and reports any containers in an exited state for quick troubleshooting.
9. Logs actions under `/var/log/backbone-bootstrap.log`.

Re-run on the droplet for troubleshooting:
```bash
sudo bash /opt/backbone-infa/cloud-init.sh
```

---

## Docker & Caddy Stack

Located in `docker/docker-compose.yml`:

- **Caddy** listens on ports 80/443, reads global config from `docker/Caddyfile`, and imports site snippets from `docker/sites/*.caddy`. TLS certificates are stored in the `caddy_data` volume.
- **Optional containers** (disabled by default using Compose profiles):
  - `watchtower` (profile `updates`) — automated image updates.
  - `uptime-kuma` & `netdata` (profile `monitoring`) — observability stack; expose them via Caddy by adding site snippets rather than host port mappings.
  - `backups` (profile `backups`) — Restic container placeholder for future backup automation.
- **Networking hygiene** keeps only ports 80/443 published on the host. All other services attach to the `backbone` bridge and surface through Caddy.
- **Networks & volumes** are pre-defined (`backbone` network, persistent volumes for Caddy/monitoring/backups).

Useful commands:
```bash
docker compose -f docker/docker-compose.yml config   # validate syntax
docker compose up -d                                 # start core stack
docker compose --profile monitoring up -d            # enable monitoring profile
docker compose logs -f caddy                         # tail Caddy logs
```

---

## Service Onboarding

### Add a new service

1. **Copy the template scaffolding:**
   ```bash
   mkdir -p services/<name>
   cp templates/service-template/docker-compose.snippet.yml "services/<name>/docker-compose.snippet.yml"
   cp templates/service-template/Caddyfile.snippet "docker/sites/<name>.caddy"
   ```
2. **Edit placeholders** in the new snippets (`<name>` service block and `reverse_proxy` target port).
3. **Add environment values** to `.env` following the `SERVICE_<NAME>_` convention (image, domain, internal port).
4. **Append the Compose snippet** into `docker/docker-compose.yml` within the `services:` section.
5. **Confirm the Caddy snippet** lives under `docker/sites/`; the main `Caddyfile` imports everything in that directory automatically.
6. **Validate & run:**
   ```bash
   docker compose -f docker/docker-compose.yml config
   docker compose up -d
   ```

### Helper script

The helper script automates those steps, enforces unique names/domains/ports, and prints the follow-up tasks:

```bash
scripts/add-service.sh blog blog.example.com 8080
```

It generates:
- `services/blog/docker-compose.snippet.yml`
- `docker/sites/blog.caddy`

Review the generated files, commit them, and populate the suggested keys in `.env` before starting the stack.

---

## Environment Variables

- `.env` (copied from `.env.example`) is consumed by Docker Compose and Caddy.
- Keys follow the convention `SERVICE_<NAME>_VARIABLE`. Example:
  ```dotenv
  CADDY_ADMIN_EMAIL=admin@example.com
  SERVICE_BLOG_IMAGE=ghcr.io/example/blog:latest
  SERVICE_BLOG_DOMAIN=blog.example.com
  SERVICE_BLOG_PORT=8080
  ```
- Secrets (database passwords, API keys) should be injected via `.env` or a secure secrets manager—never committed.

---

## Optional Profiles & Future Modules

- **`updates` profile:** Enables Watchtower to keep containers up to date.
- **`monitoring` profile:** Runs Uptime Kuma + Netdata. Add Caddy site snippets if you wish to expose dashboards.
- **`backups` profile:** Restic container with placeholder command—customize before enabling.

Terraform remains focused on the single droplet baseline, but structure is ready for optional modules (monitoring, backups, etc.) in future iterations. When you are ready, enable the `monitoring` profile for Uptime Kuma/Netdata and build on the `backups` profile to capture Restic snapshots.

---

## Scripts

- `scripts/add-service.sh` — Scaffolds Compose and Caddy snippets for new services and validates that service names, domains, and internal ports are unique.

Usage recap:
```bash
scripts/add-service.sh <service-name> <domain> [internal-port]
```

The script prints next steps, including environment keys to populate and files to edit.

---

## CI / Automation

GitHub Actions workflow `.github/workflows/terraform.yml` runs on pushes/PRs touching infrastructure, Docker, or script files. It performs:

1. `yamllint` across Docker, template, and workflow YAML.
2. `shellcheck` for `cloud-init.sh` and helper scripts.
3. `docker compose -f docker/docker-compose.yml config` with the example `.env`.
4. `terraform fmt -check`
5. `terraform init -backend=false`
6. `terraform validate`

Add additional tooling (e.g., `hadolint`) when Dockerfiles enter the repo.

---

## Troubleshooting

| Issue | Resolution |
| ----- | ---------- |
| `terraform init` fails (no registry access) | Ensure outbound internet; in air-gapped environments, vendor providers manually or run with `-backend=false` just for validation. |
| Droplet provisioned but Caddy missing | Tail `/var/log/backbone-bootstrap.log`; rerun `cloud-init.sh` and check `docker compose ps --status=running caddy`. |
| SSL issuance fails | Verify DNS A records point at `droplet_ip`, confirm ports 80/443 are permitted by both DigitalOcean and UFW, and inspect `docker compose logs --tail=100 caddy`. |
| Container exits immediately | `docker compose ps --status=exited` shows offenders; inspect logs and confirm environment variables are set. The bootstrap script prints these containers if it detects failures. |
| Service unreachable | Ensure the Compose snippet uses `expose` (not `ports`) and that a matching Caddy site exists under `docker/sites/`. Domains must be unique per service. |
| Need to update repo on droplet | `git -C /opt/backbone-infa pull` or rerun `cloud-init.sh`. |

Logs of interest:
- `/var/log/cloud-init-output.log`
- `/var/log/backbone-bootstrap.log`
- `docker logs backbone-caddy`

---

## Reference Commands

```bash
# Show Terraform outputs in friendly form
terraform -chdir=terraform output

# Arm Compose with remote Docker host
export DOCKER_HOST="$(terraform -chdir=terraform output -raw docker_host)"

# Tail Caddy logs
docker compose -f docker/docker-compose.yml logs -f caddy

# Re-run bootstrap (idempotent)
sudo bash /opt/backbone-infa/cloud-init.sh

# Remove droplet & resources
terraform -chdir=terraform destroy
```

---

## License

MIT © Dylan Steele. Contributions welcome—open issues or PRs if you have improvements, monitoring modules, or backup strategies to share.
