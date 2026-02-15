# Backbone Infrastructure

Single-droplet DigitalOcean setup for:

- Static sites via Caddy
- Umami analytics + Postgres
- Small internal/test services behind Caddy

Terraform provisions infra. Host bootstrap scripts configure the server. Docker Compose runs runtime services.

## What Is Customized In This Repo

- `setup-backbone.sh` hardening and safety:
  - Creates/repairs `ubuntu` SSH key access before SSH hardening.
  - Root SSH is disabled by default (`DISABLE_ROOT_SSH=true`).
  - Root SSH can be temporarily enabled for debugging (`DISABLE_ROOT_SSH=false`).
  - UFW + `ufw-docker` rules for Caddy ports.
  - Fail2ban for SSH.
- DNS tooling:
  - `scripts/check-dns.sh` for local/global DNS visibility checks.
  - `scripts/check-acme-readiness.sh` for authoritative DNS convergence checks before ACME retries.
- Umami reliability:
  - `umami-db` has a healthcheck (`pg_isready`).
  - `umami` waits for DB health (`depends_on: service_healthy`).
- Terraform DNS automation:
  - Opt-in via helper script env flag (`ENABLE_TERRAFORM_DNS_AUTOMATION=true`).
  - Default workflow leaves DNS manual unless explicitly enabled.

## Repo Layout

```text
terraform/                 # DO droplet, firewall, optional DNS records
docker/                    # compose stack + Caddy config + bundled static content
scripts/                   # DNS checks, tf helper, Umami ops/backup scripts
templates/service-template/# snippets for adding new services
setup-backbone.sh          # full host setup/repair script
cloud-init.sh              # first-boot bootstrap path
UMAMI_LOGIN_RUNBOOK.md     # deep Umami login troubleshooting
```

## Prerequisites

- Terraform `>= 1.5`
- DigitalOcean API token
- SSH public key (or existing DO SSH key fingerprint)
- Domain zone hosted in DigitalOcean DNS (if using this domain/certs flow)

## Environment Files

- `docker/.env`: runtime config for Docker Compose
- `.env` (repo root): helper script config (for example `scripts/tf-plan.sh`)

Create from examples:

```bash
cp docker/.env.example docker/.env
cp .env.example .env
```

## Infra Provisioning (Terraform)

Recommended (helper script):

```bash
bash scripts/tf-plan.sh plan
bash scripts/tf-plan.sh apply
```

This uses root `.env` values (for example `DO_TOKEN`, optional SSH/DNS overrides), exports `TF_VAR_*`, runs `terraform init`, then `plan`/`apply`.

Direct Terraform commands (fallback):

```bash
export TF_VAR_do_token="<digitalocean-token>"
terraform -chdir=terraform init
terraform -chdir=terraform plan -out backbone.tfplan
terraform -chdir=terraform apply backbone.tfplan
```

Important behavior:

- Existing DO SSH key: set `TF_VAR_ssh_key_fingerprint`.
- DNS automation is opt-in, not default.
- Managed DNS (when enabled) targets `@`, `www`, `blog`, `umami`.

## Host Bootstrap

Default path is Terraform + cloud-init. Manual/repair path:

```bash
scp setup-backbone.sh ubuntu@<droplet-ip>:/tmp/
ssh ubuntu@<droplet-ip>
sudo ROOT_DOMAIN=example.com CADDY_EMAIL=ops@example.com BRANCH=main bash /tmp/setup-backbone.sh
```

Debug override (keep root SSH enabled temporarily):

```bash
sudo DISABLE_ROOT_SSH=false ROOT_DOMAIN=example.com CADDY_EMAIL=ops@example.com BRANCH=main bash /tmp/setup-backbone.sh
```

## Runtime Operations

Validate compose:

```bash
docker compose -f docker/docker-compose.yml --env-file docker/.env config
```

Start:

```bash
docker compose -f docker/docker-compose.yml --env-file docker/.env up -d
```

Logs:

```bash
docker compose -f docker/docker-compose.yml --env-file docker/.env logs -f caddy
docker compose -f docker/docker-compose.yml --env-file docker/.env logs -f umami
```

## DNS + ACME Checks (Fast Path)

From your Mac:

```bash
bash scripts/check-dns.sh dsteele.dev 45.55.234.244
```

From droplet:

```bash
bash /root/check-acme-readiness.sh dsteele.dev 45.55.234.244
```

If converged, restart Caddy once:

```bash
docker compose -f /opt/backbone-infa/docker/docker-compose.yml --env-file /opt/backbone-infa/docker/.env restart caddy
```

## Umami Ops

Safe update:

```bash
bash scripts/update-umami.sh
```

Backups:

```bash
BACKUP_PASSPHRASE='replace-me' bash scripts/backup-umami-db.sh
```

Restore:

```bash
BACKUP_PASSPHRASE='replace-me' bash scripts/restore-umami-db.sh --file <backup-file> --drop-existing
```

## Troubleshooting Index

- Umami login issues:
  - Use `UMAMI_LOGIN_RUNBOOK.md` (primary runbook).
- DNS looks right in UI but certs fail:
  - Run non-recursive authoritative checks (`scripts/check-acme-readiness.sh`).
- Let's Encrypt `429 rateLimited`:
  - Wait until the exact retry timestamp shown in Caddy logs; do not spam restarts.
- macOS still resolving old IP:
  - `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`
- Local `terraform validate` provider handshake errors:
  - Re-run init/upgrade and verify local provider binary compatibility.

## CI

- Terraform workflow: lint, shellcheck, compose config validation, terraform checks.
- Security workflow: Trivy filesystem and image scans.

## License

MIT © Dylan Steele
