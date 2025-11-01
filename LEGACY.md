# Legacy Notes

This repository previously relied on an Nginx + Certbot stack alongside manual per-service Docker Compose files. The refactor to Caddy with automatic TLS and service templates retires those assets. Historical artifacts including `.docker/nginx/` and the older `terraform.action.yml` workflow have been removed from source. Refer to Git history prior to PR #10 if you need to recover the legacy implementation details.

# End-of-life components

- Nginx reverse proxy configuration.
- Certbot automation scripts for certificate issuance/renewal.
- Ad-hoc per-service Compose definitions outside the new `templates/service-template/` workflow.

The new Caddy-first approach centralizes HTTPS management and uses `docker/sites/*.caddy` imports, while the onboarding script keeps service boilerplate consistent.
