# Deployment Guide

This repository contains independent Docker Compose projects under `stacks/<name>/`. Deploy each stack with its own stack-local environment and compose file. Public HTTP services publish host ports, usually on `127.0.0.1`, and are routed by Caddy snippets merged into the host Caddyfile.

## Prerequisites

- Docker Engine with Docker Compose v2
- A host with ports 80 and 443 available to Caddy
- DNS records for the hostnames used by the stack Caddyfiles
- The external `dokploy-network` network, created by Dokploy or manually

## Environment Files

Copy each stack's example file and fill in real values:

```bash
cp stacks/databases/.env.example stacks/databases/.env
cp stacks/cache/.env.example stacks/cache/.env
cp stacks/activepieces/.env.example stacks/activepieces/.env
cp stacks/automation/.env.example stacks/automation/.env
```

Keep real `.env` files, `.backup`, credentials, and database data out of Git. Several Compose variables use `${VAR:?message}`; an example file may omit or misname a required value, so validate with the real stack `.env` before deployment.

## Deployment Order

Create the external network once:

```bash
docker network create dokploy-network
```

Deploy database and cache dependencies first:

```bash
docker compose -f stacks/databases/docker-compose.yml up -d
docker compose -f stacks/cache/docker-compose.yml up -d
```

Then deploy application stacks in dependency order:

```bash
docker compose -f stacks/automation/docker-compose.yml up -d
docker compose -f stacks/activepieces/docker-compose.yml up -d
docker compose -f stacks/monitoring/docker-compose.yml up -d
docker compose -f stacks/beszel/docker-compose.yml up -d
docker compose -f stacks/netdata/docker-compose.yml up -d
docker compose -f stacks/fuelrod/docker-compose.yml up -d
docker compose -f stacks/farm/docker-compose.yml up -d
docker compose -f stacks/akilimo/docker-compose.yml up -d
docker compose -f stacks/fees-prod/docker-compose.yml up -d
docker compose -f stacks/fees-dev/docker-compose.yml up -d
```

Do not add `--project-directory .` to these commands. Relative bind mounts such as `../../config/...` and stack-local `.env` loading depend on the compose file's directory.

## Activepieces

The Activepieces stack has separate `app` and `worker` services. The app uses the shared PostgreSQL service at `postgres` and Redis at `cache`; the worker connects only to the app and uses a generated worker token.

The PostgreSQL database name is `activepieces`. It is listed in `stacks/databases/.env.example`, but initialization only creates databases when `pgdata-main` is empty. On an existing database volume, create it explicitly with the shared PostgreSQL owner before starting Activepieces.

Set these values in `stacks/activepieces/.env`:

```dotenv
AP_FRONTEND_URL=https://flow.munywele.co.ke
AP_ENCRYPTION_KEY=<openssl rand -hex 16>
AP_JWT_SECRET=<openssl rand -hex 32>
AP_WORKER_TOKEN=<generated with the same AP_JWT_SECRET>
POSTGRES_USER=<shared PostgreSQL user>
POSTGRES_PASSWORD=<shared PostgreSQL password>
REDIS_PASSWORD=<shared Redis password or empty>
```

Generate the worker token with:

```bash
npx @activepieces/cli workers token
```

Validate and start the stack:

```bash
docker compose --env-file stacks/activepieces/.env \
  -f stacks/activepieces/docker-compose.yml config --quiet
docker compose -f stacks/activepieces/docker-compose.yml up -d
curl http://127.0.0.1:9710/api/v1/health
```

Fees production and development are independent Compose projects. Start `fees-prod` and `fees-dev` separately; a production update does not restart the development container. Merge each stack's Caddy snippet into the host Caddyfile.

## Beszel

The standalone Beszel stack runs the hub on `127.0.0.1:9625` and an agent internally. Start the hub first, open `http://127.0.0.1:9625` through an SSH tunnel, create a universal token under **Settings → Tokens**, and set it in `stacks/beszel/.env`. The agent auto-registers with the hub and does not require a per-system public key:

```dotenv
BESZEL_UNIVERSAL_TOKEN=<token from Settings → Tokens>
```

The hub UI can also be exposed at `beszel.munywele.co.ke` using `stacks/beszel/Caddyfile`.

## Caddy Routing

Merge the relevant stack snippet into the host Caddyfile. Activepieces uses:

```text
flow.munywele.co.ke → 127.0.0.1:9710
```

The monitoring stack uses Grafana, Prometheus, Loki, Alloy, cAdvisor, PostgreSQL Exporter, and Redis Exporter. Set `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `REDIS_PASSWORD` in `stacks/monitoring/.env` to enable the database/cache dashboards. Grafana provides the browser UI for Loki logs at `logs.munywele.co.ke` through the Caddy snippet, while the separate `stacks/netdata/` stack monitors host and container metrics.

Validate before reloading:

```bash
caddy adapt --config stacks/activepieces/Caddyfile --adapter caddyfile
caddy validate --config /etc/caddy/Caddyfile
sudo caddy reload --config /etc/caddy/Caddyfile
```

The stack Caddyfile is a snippet, not a complete replacement for the host Caddyfile.

## Updating a Stack

Use the same stack directory and environment file for all operations:

```bash
docker compose -f stacks/activepieces/docker-compose.yml pull
docker compose -f stacks/activepieces/docker-compose.yml up -d
docker compose -f stacks/activepieces/docker-compose.yml logs -f app
```

Validate a compose change without printing resolved secrets:

```bash
docker compose --env-file stacks/<stack>/.env \
  -f stacks/<stack>/docker-compose.yml config --quiet
```

## Adding a Stack

1. Create `stacks/<name>/docker-compose.yml` and keep bind mounts relative to that directory.
2. Join the external `dokploy-network` when cross-stack access is required.
3. Add a stack-local `.env.example`; never commit the real `.env`.
4. Add a stack Caddyfile when the service needs a public hostname.
5. Update `docs/ports.md` and the repository inventory with the stack's actual service names, dependencies, and ports.
6. Validate Compose and Caddy configuration before deployment.
