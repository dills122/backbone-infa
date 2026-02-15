# Umami Login Troubleshooting Runbook

Use this when `https://umami.<your-domain>` login fails (UI error, 500, or auth loop).

## 1) Capture Data First (Do Not Restart Yet)

Run these on the droplet and save the output:

```bash
docker compose -f /opt/backbone-infa/docker/docker-compose.yml --env-file /opt/backbone-infa/docker/.env ps
docker compose -f /opt/backbone-infa/docker/docker-compose.yml --env-file /opt/backbone-infa/docker/.env logs --tail=200 umami umami-db caddy
docker inspect backbone-umami --format '{{json .State.Health}}'
docker inspect backbone-umami-db --format '{{json .State.Health}}'
```

Also capture:
- UTC timestamp of failure
- URL used
- Browser error message
- HTTP status/response from browser network tab for login request

## 2) Quick Recovery

If `umami-db` is healthy but login is failing, restart Umami only:

```bash
docker compose -f /opt/backbone-infa/docker/docker-compose.yml --env-file /opt/backbone-infa/docker/.env restart umami
```

Then tail logs:

```bash
docker compose -f /opt/backbone-infa/docker/docker-compose.yml --env-file /opt/backbone-infa/docker/.env logs -f --tail=120 umami
```

If needed, restart full stack:

```bash
docker compose -f /opt/backbone-infa/docker/docker-compose.yml --env-file /opt/backbone-infa/docker/.env restart
```

## 3) If HTTPS/DNS Looks Wrong

Validate authoritative DNS first:

```bash
bash /root/check-acme-readiness.sh dsteele.dev 45.55.234.244
```

If not converged, do not force repeated caddy restarts.

## 4) Rate Limit Reminder (Let's Encrypt)

If caddy logs show `HTTP 429 ... rateLimited`, wait until the exact retry time in logs.
Repeated retries before that time only prolong failure loops.

## 5) Last Resort (Destructive)

Only if you intentionally want a fresh Umami database:

```bash
docker compose -f /opt/backbone-infa/docker/docker-compose.yml --env-file /opt/backbone-infa/docker/.env down
docker volume rm docker_umami_data
docker compose -f /opt/backbone-infa/docker/docker-compose.yml --env-file /opt/backbone-infa/docker/.env up -d
docker logs backbone-umami 2>&1 | grep -i ADMIN_CREDENTIALS
```

This deletes all Umami analytics data.
