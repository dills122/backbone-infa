# Backbone Infrastructure

Infrastructure and runtime stack for a single DigitalOcean droplet that hosts:

- Static sites via Caddy (`file_server`)
- Umami analytics + Postgres
- Small internal/test services behind Caddy

Terraform provisions the droplet and firewall. `cloud-init.sh` bootstraps the host. Docker Compose runs the runtime services.

## Current Architecture

- Terraform:
  - Creates one droplet (`digitalocean_droplet.backbone_server_1`)
  - Creates one cloud firewall (`digitalocean_firewall.backbone_server_1`)
  - Optionally manages DNS A records (`digitalocean_record.backbone_a_records`)
  - Injects `cloud-init.sh` as droplet `user_data`
- Host bootstrap:
  - Installs Docker + Compose plugin
  - Enables UFW, Fail2ban, SSH hardening
  - Ensures `ubuntu` user has SSH key access before disabling root SSH login
  - Clones repo to `/opt/backbone-infa`
- Runtime stack (`docker/docker-compose.yml`):
  - `caddy`
  - `umami-db` (Postgres, healthchecked with `pg_isready`)
  - `umami` (starts after `umami-db` is healthy)
- Caddy routing:
  - Base routes in `docker/Caddyfile`
  - Additional routes imported from `docker/sites.d/*.caddy`

## Repository Layout

```text
terraform/
  main.tf
  variables.tf
  outputs.tf

docker/
  docker-compose.yml
  Caddyfile
  .env.example
  sites/               # bundled static source content
  sites.d/             # extra Caddy site blocks

scripts/
  add-service.sh
  update-umami.sh
  backup-umami-db.sh
  restore-umami-db.sh
  install-umami-backup-cron.sh
  tf-plan.sh
  check-dns.sh
  check-acme-readiness.sh

templates/service-template/
  docker-compose.snippet.yml
  Caddyfile.snippet

cloud-init.sh
setup-backbone.sh
UMAMI_LOGIN_RUNBOOK.md
.env.example
```

## Prerequisites

- Terraform `>= 1.5`
- DigitalOcean API token
- SSH public key available locally (default: `~/.ssh/id_ed25519.pub`) or an existing DigitalOcean SSH key fingerprint
- Docker CLI + Compose plugin (for local validation/remote operations)
- Domain zone hosted in DigitalOcean DNS if you enable Terraform DNS automation

## Terraform Setup

Set required Terraform vars:

```bash
export TF_VAR_do_token="<digitalocean-token>"
```

Optional useful vars:

```bash
export TF_VAR_caddy_admin_email="ops@example.com"
export TF_VAR_ssh_allowed_cidrs='["0.0.0.0/0","::/0"]'
```

SSH key behavior:

- If `TF_VAR_ssh_key_fingerprint` is set, Terraform uses that existing DO key.
- If it is empty, Terraform can create/use a DigitalOcean SSH key from `ssh_public_key`/`ssh_public_key_path`.

DNS behavior:

- DNS automation is disabled by default in `scripts/tf-plan.sh`.
- To opt in, set `ENABLE_TERRAFORM_DNS_AUTOMATION=true` and provide DNS vars in your root `.env`.
- If enabled with `manage_dns_records=true` and `domain_name` set, Terraform manages `@`, `www`, `blog`, and `umami` A records pointing at the droplet IP.
- The domain zone must already exist in DigitalOcean DNS.

Plan/apply:

```bash
terraform -chdir=terraform init
terraform -chdir=terraform plan -out backbone.tfplan
terraform -chdir=terraform apply backbone.tfplan
```

Outputs:

```bash
terraform -chdir=terraform output
```

Key outputs:

- `droplet_ip`
- `ssh_command`
- `ssh_command_ubuntu`
- `docker_host`
- `firewall_id`
- `managed_dns_records`

## Runtime Environment Files

- `docker/.env`:
  - Used by Docker Compose runtime services
  - Start from `docker/.env.example`
- `.env` (repo root):
  - Used by helper scripts like `scripts/tf-plan.sh`
  - Start from `.env.example`

Create both files locally:

```bash
cp docker/.env.example docker/.env
cp .env.example .env
```

## Host Bootstrap Paths

### Path A: Terraform + cloud-init (default)

After `terraform apply`, cloud-init runs automatically on first boot.

To re-run on host:

```bash
sudo bash /opt/backbone-infa/cloud-init.sh
```

### Path B: setup-backbone.sh (manual/repair path)

`setup-backbone.sh` is a full host setup script for a fresh Ubuntu host.

Example:

```bash
scp setup-backbone.sh ubuntu@<droplet-ip>:/tmp/
ssh ubuntu@<droplet-ip>
sudo ROOT_DOMAIN=example.com CADDY_EMAIL=ops@example.com BRANCH=main bash /tmp/setup-backbone.sh
```

If `BACKUP_PASSPHRASE` is provided, it also installs scheduled encrypted Umami backups.

## Docker and Caddy

Validate config:

```bash
docker compose -f docker/docker-compose.yml --env-file docker/.env config
```

Start stack:

```bash
docker compose -f docker/docker-compose.yml --env-file docker/.env up -d
```

Logs:

```bash
docker compose -f docker/docker-compose.yml --env-file docker/.env logs -f caddy
docker compose -f docker/docker-compose.yml --env-file docker/.env logs -f umami
```

## Static Sites

Current default Caddy config serves:

- Root domain from `/srv/sites/coming-soon`
- Blog subdomain from `/srv/sites/blog`

These map to host path `/opt/backbone-infa/sites/*` via bind mount.

Bundled source content lives in `docker/sites/*` and is seeded to `/opt/backbone-infa/sites/*` by bootstrap scripts.

## Adding a Service

Generate snippets:

```bash
scripts/add-service.sh <service-name> <domain> [internal-port]
```

This creates:

- `services/<service-name>/docker-compose.snippet.yml`
- `docker/sites.d/<service-name>.caddy`

Then:

- Append the Compose snippet under `services:` in `docker/docker-compose.yml`
- Add required env keys to `docker/.env`
- Validate and deploy Compose

## Umami Operations

### Update Umami Safely

```bash
bash scripts/update-umami.sh
bash scripts/update-umami.sh --image ghcr.io/umami-software/umami:postgresql-latest
```

What it does:

- Pulls target image
- Pins resolved image digest/tag to `UMAMI_IMAGE` in `docker/.env`
- Restarts only `umami`
- Probes via Caddy
- Rolls back on failure

### Backup Umami DB (encrypted)

```bash
BACKUP_PASSPHRASE='replace-me' bash scripts/backup-umami-db.sh
```

### Restore Umami DB

```bash
BACKUP_PASSPHRASE='replace-me' \
  bash scripts/restore-umami-db.sh \
  --file /opt/backbone-infa/backups/umami/umami-db-YYYYMMDDTHHMMSSZ.sql.gz.enc \
  --drop-existing
```

### Install Scheduled Backups

```bash
sudo BACKUP_PASSPHRASE='replace-me' bash scripts/install-umami-backup-cron.sh
```

Optional env overrides:

- `BACKUP_DIR`
- `RETENTION_DAYS`
- `CRON_SCHEDULE`
- `RUN_NOW=true`

## Security Controls in Current Implementation

- DigitalOcean cloud firewall:
  - Inbound TCP `22`, `80`, `443`
  - SSH source CIDRs controlled by `ssh_allowed_cidrs`
- UFW defaults + explicit `OpenSSH`, `80/tcp`, `443/tcp`
- `ufw limit OpenSSH`
- SSH hardening:
  - `PermitRootLogin no` only when setup is run with `DISABLE_ROOT_SSH=true`
  - `PasswordAuthentication no`
  - `KbdInteractiveAuthentication no`
  - `ChallengeResponseAuthentication no`
  - `PubkeyAuthentication yes`
- Fail2ban (`sshd` jail)

## CI Workflows

- `.github/workflows/terraform.yml`:
  - `yamllint`
  - `shellcheck`
  - Compose config validation
  - `terraform fmt -check`
  - `terraform init -backend=false`
  - `terraform validate`
- `.github/workflows/security.yml`:
  - Trivy filesystem scan (`CRITICAL`)
  - Trivy image scan for Compose images (`CRITICAL`)

## Troubleshooting

### Core service status

- Check stack state:
  - `docker compose -f /opt/backbone-infa/docker/docker-compose.yml --env-file /opt/backbone-infa/docker/.env ps`
- Check Caddy/Umami logs:
  - `docker compose -f /opt/backbone-infa/docker/docker-compose.yml --env-file /opt/backbone-infa/docker/.env logs --tail=200 caddy umami umami-db`

### DNS and TLS (most common failure mode)

- Run full DNS visibility check from local machine:
  - `bash scripts/check-dns.sh dsteele.dev 45.55.234.244`
- Run ACME-readiness check on droplet:
  - `bash /root/check-acme-readiness.sh dsteele.dev 45.55.234.244`
- If DNS is fully converged, restart caddy once:
  - `docker compose -f /opt/backbone-infa/docker/docker-compose.yml --env-file /opt/backbone-infa/docker/.env restart caddy`

### When DNS appears correct in UI but certs still fail

- Query authoritative nameservers directly with non-recursive lookups:
  - `for ns in ns1.digitalocean.com ns2.digitalocean.com ns3.digitalocean.com; do echo "=== $ns ==="; dig +norecurse +noall +answer @"$ns" dsteele.dev A; dig +norecurse +noall +answer @"$ns" blog.dsteele.dev A; dig +norecurse +noall +answer @"$ns" umami.dsteele.dev A; done`
- If any nameserver returns an old IP, ACME may validate against the wrong host and fail.
- If macOS is stale locally, flush cache:
  - `sudo dscacheutil -flushcache && sudo killall -HUP mDNSResponder`

### Let's Encrypt rate limiting

- If caddy logs contain `HTTP 429 ... rateLimited`, wait until the exact retry timestamp in logs.
- Do not repeatedly restart caddy before that timestamp.

### Umami login failures

- Use `/Users/dsteele/repos/backbone-infa/UMAMI_LOGIN_RUNBOOK.md` for the exact data-capture and recovery sequence.
- Quick recovery (non-destructive):
  - `docker compose -f /opt/backbone-infa/docker/docker-compose.yml --env-file /opt/backbone-infa/docker/.env restart umami`

### Terraform local plugin issue on macOS

- If `terraform validate` fails with provider schema/plugin handshake errors:
  - `terraform -chdir=terraform init -upgrade`
  - Verify provider binary architecture/dylib compatibility with your local machine.

## License

MIT © Dylan Steele
