# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A Docker Compose orchestration layer for multiple independent application stacks (Fuelrod, Akilimo, Use-Uptake, Fees, Farm, Sonar, Metabase, Activepieces, and supporting tooling) on a shared host. Public routing and TLS are handled by host Caddy snippets. `dokploy-network` is external and shared; stacks also commonly join a fixed-name `internal` network.

## Common Commands

### Starting Stacks

Stack files live at `stacks/<name>/docker-compose.yml`. Deploy in dependency order:

```bash
# 1. External network required by the stacks
docker network create dokploy-network

# 2. Databases — must start first (postgres, pgbouncer, maria)
docker compose -f stacks/databases/docker-compose.yml up -d

# 3. Cache — separate Redis stack
docker compose -f stacks/cache/docker-compose.yml up -d

# 4. Automation — requires databases (n8n)
docker compose -f stacks/automation/docker-compose.yml up -d

# 5. Activepieces — requires databases, cache, and the activepieces database
docker compose -f stacks/activepieces/docker-compose.yml up -d

# 6. Monitoring — Loki and Alloy
docker compose -f stacks/monitoring/docker-compose.yml up -d
docker compose -f stacks/netdata/docker-compose.yml up -d

# 4. Fuelrod — requires databases; creates the shared 'uploads' volume
docker compose -f stacks/fuelrod/docker-compose.yml up -d

# 5. Farm — requires databases + fuelrod (uses the 'uploads' volume)
docker compose -f stacks/farm/docker-compose.yml up -d

# 6. Akilimo — requires databases (MariaDB)
docker compose -f stacks/akilimo/docker-compose.yml up -d

# 7. Use-Uptake — requires akilimo (connects to Akilimo API)
docker compose -f stacks/use-uptake/docker-compose.yml up -d

# 8. Fees production — requires databases
# 9. Fees development — independent from production
docker compose -f stacks/fees-prod/docker-compose.yml up -d
docker compose -f stacks/fees-dev/docker-compose.yml up -d

# --- Optional / tooling stacks (order independent) ---
docker compose -f stacks/sonar/docker-compose.yml up -d
docker compose -f stacks/metabase/docker-compose.yml up -d
docker compose -f stacks/mail/docker-compose.yml up -d
docker compose -f stacks/mqtt/docker-compose.yml up -d
docker compose -f stacks/db-tools/docker-compose.yml up -d
docker compose -f stacks/dozzle/docker-compose.yml up -d

# Start a single service within a stack
docker compose -f stacks/databases/docker-compose.yml up -d postgres
```

### Backup & Restore

The repository contains backup script samples under `scripts/`, but no active backup tool or database migration project. Use the deployment's database tooling and keep backup data and credentials outside Git.

### Utilities

The scripts under `scripts/` are operational helpers and include destructive or host-wide actions. Read a script before running it; do not assume a similarly named root-level script exists.

## Architecture

### Compose Structure

Each stack is a self-contained `docker-compose.yml` with no `include:` directives. Bind-mount paths in each compose file are **relative to that compose file's own directory**. To reference shared config at the repo root from `stacks/<name>/docker-compose.yml`, use the `../../` prefix (e.g. `../../config/supervisor/common`).

```
stacks/
  ├── databases/          ← postgres 17, pgbouncer, mariadb
  ├── cache/              ← Redis production and development
  ├── automation/         ← n8n
  ├── activepieces/       ← Activepieces app + worker
  ├── monitoring/         ← Grafana, Prometheus, Loki, Alloy
  ├── beszel/             ← Beszel hub and host agent
  ├── netdata/            ← Netdata host/container metrics
  ├── fuelrod/            ← Fuelrod service, SMS portal, SMS gateway
  ├── farm/               ← Farm Manager API, web, migrations
  ├── akilimo/            ← Akilimo API (Laravel)
  ├── use-uptake/         ← Use-Uptake frontend
  ├── fees-prod/          ← Production Fee Syncer
  ├── fees-dev/           ← Development Fee Syncer
  ├── sonar/              ← SonarQube (optional)
  ├── metabase/           ← Metabase BI (optional)
  ├── mail/               ← Mailpit SMTP relay (optional)
  ├── mqtt/               ← EMQX MQTT broker (optional)
  ├── db-tools/           ← Adminer + RedisInsight (optional)
  └── dozzle/             ← Docker log viewer (optional)
config/
  ├── supervisor/         ← Supervisor process configs per app (common/, fuelrod/, fees/, akilimo/)
  ├── nginx/              ← NGINX configs
  ├── monitoring/         ← Grafana, Prometheus, Loki, Alloy
  ├── beszel/             ← Beszel hub and host agent
  ├── netdata/            ← Netdata host/container metrics
  └── init/pgsql/         ← PostgreSQL init scripts (run on first container start)
log/
  └── supervisor/         ← Bind-mounted log directories (fees.prod/, fees.dev/)
stacks/databases/
  └── postgres/           ← postgres.conf (bind-mounted into the postgres container)
```

### PostgreSQL Initialisation

On first start (empty data volume), postgres runs every file in `config/init/pgsql/` in sorted order:

| Script | Purpose |
|--------|---------|
| `00-extensions.sql` | Enables `uuid-ossp` and `pg_stat_statements` on the primary DB |
| `01-databases.sh` | Creates databases listed in `ADDITIONAL_DBS` (comma-separated); enables `uuid-ossp` on each |

`shared_preload_libraries = 'pg_stat_statements'` is set in `stacks/databases/postgres/postgres.conf`.

### Environment Files

Each stack folder has its own `.env` (gitignored) and `.env.example` (tracked). Docker Compose auto-loads `.env` from the same directory as the compose file — no `--env-file` flags needed.

Stacks that share postgres credentials must use matching values — copy from `stacks/databases/.env`.

| Stack `.env` | Services configured |
|---|---|
| `stacks/databases/.env` | postgres, pgbouncer, mariadb |
| `stacks/cache/.env` | production and development Redis passwords |
| `stacks/activepieces/.env` | Activepieces public URL, secrets, worker token, shared PostgreSQL credentials, optional Redis password |
| `stacks/automation/.env` | n8n (postgres creds must match databases) |
| `stacks/monitoring/.env` | Grafana, Prometheus, Loki, and Alloy settings |
| `stacks/beszel/.env` | Beszel hub/agent keys, token, and resource settings |
| `stacks/netdata/.env` | Netdata image and resource settings |
| `stacks/fuelrod/.env` | Fuelrod, SMS portal, SMS gateway |
| `stacks/farm/.env` | Farm API, web, migrations (postgres creds must match databases) |
| `stacks/akilimo/.env` | Akilimo API |
| `stacks/use-uptake/.env` | Use-Uptake frontend |
| `stacks/fees-prod/.env` | Production Fee Syncer |
| `stacks/fees-dev/.env` | Development Fee Syncer |
| `stacks/sonar/.env` | SonarQube (postgres creds must match databases) |
| `stacks/metabase/.env` | Metabase (postgres creds must match databases) |
| `stacks/mail/.env` | Mailpit |
| `stacks/mqtt/.env` | EMQX MQTT broker |
| `stacks/db-tools/.env` | Adminer, RedisInsight |
| `stacks/dozzle/.env` | Dozzle |
| `.backup` | Backup scripts only (sourced at runtime, gitignored) |

### Service Configuration

Laravel-based services (Fuelrod, Fees, Akilimo) use Supervisor inside their containers. Supervisor configs live in `config/supervisor/<app>/` and are bind-mounted into the container with `../../config/supervisor/...` paths. Each `.conf` file manages one process (nginx, php-fpm, scheduler, queue workers, etc.).

### Networking

- `dokploy-network`: external, created by Dokploy on install. All inter-stack communication uses this network. Create manually with `docker network create dokploy-network` when running without Dokploy.
- `internal`: commonly declared with the fixed name `internal`; despite older documentation calling it private or per-stack, current Compose projects share that network.
- Public HTTP services publish loopback ports and are routed through stack Caddyfiles merged into the host Caddyfile.

### Cross-Stack Volumes

| Volume | Created by | Consumed by | Purpose |
|---|---|---|---|
| `uploads` | farm | — | Farm uploads |
| `fuelrod-uploads` | fuelrod | — | Fuelrod uploads |

Application logs are emitted to container stdout and collected through the
Docker socket by Alloy.

### Monitoring Stack

`stacks/monitoring/docker-compose.yml` runs Grafana, Prometheus, Loki, and Alloy. `stacks/netdata/docker-compose.yml` runs Netdata independently for host and Docker metrics.

## Versioning & CI

- Commits to `main` trigger automatic SemVer tagging via `masgeek/github-tag-action`
- Commit messages drive version bumps: `fix:` → patch, `feat:` → minor, `BREAKING CHANGE:` → major
- Renovate Bot manages Docker image tag updates with semantic commit prefixes
- PRs from non-owner actors are auto-approved by the `pr-automation` workflow

## SonarQube MCP (if available)

- Always disable automatic analysis (`toggle_automatic_analysis`) at task start
- Run `analyze_file_list` on any files created or modified at task end
- Re-enable automatic analysis when done
- Look up project keys with `search_my_sonarqube_projects` — never guess them
- Use USER tokens, not project tokens (project tokens cause "Not authorized" errors)
