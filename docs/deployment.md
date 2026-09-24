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
docker compose -f stacks/fuelrod/docker-compose.yml up -d
docker compose -f stacks/farm/docker-compose.yml up -d
docker compose -f stacks/akilimo/docker-compose.yml up -d
docker compose -f stacks/fees/docker-compose.yml up -d
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

The app publishes `127.0.0.1:9710`; the worker has no published port.

## Caddy Routing

Merge the relevant stack snippet into the host Caddyfile. Activepieces uses:

```text
flow.munywele.co.ke → 127.0.0.1:9710
```

The monitoring stack uses Loki and Alloy for application logs, plus Netdata for host and container metrics. Application logs are collected from the selected Docker containers through Alloy and forwarded to Loki. Netdata runs with host PID/network access and Docker socket access, so its web listener is restricted to `127.0.0.1`; expose it only through the `monitor.munywele.co.ke` Caddy snippet. Grafana and Prometheus are not part of the active stack.

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
