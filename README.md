# Proxy Tool — Docker Compose Orchestration

Docker Compose orchestration layer for multiple independent application stacks on a shared host under **munywele.co.ke**. Public HTTP services bind loopback host ports and are routed by host Caddy snippets; TLS termination is handled by Caddy.

---

## Repository Layout

```
proxy-tool/
├── stacks/                    ← one folder per stack, each self-contained
│   ├── databases/             ← postgres 17, pgbouncer, mariadb  [deploy first]
│   ├── cache/                 ← Redis  [deploy before Redis consumers]
│   ├── automation/            ← n8n
│   ├── activepieces/          ← Activepieces app + worker
│   ├── monitoring/            ← Grafana, Prometheus, Loki, Alloy
│   ├── beszel/                ← Beszel hub and host agent
│   ├── netdata/               ← Netdata host/container metrics
│   ├── fuelrod/               ← Fuelrod service, SMS portal, SMS gateway
│   ├── farm/                  ← Farm Manager API, web, migrations
│   ├── akilimo/               ← Akilimo API, use-uptake
│   ├── fees/                  ← Fee-syncer (prod + dev)
│   ├── sonar/                 ← SonarQube  [optional]
│   ├── metabase/              ← Metabase BI  [optional]
│   ├── mail/                  ← Mailpit SMTP relay  [optional]
│   ├── mqtt/                  ← EMQX MQTT broker  [optional]
│   ├── db-tools/              ← Adminer + RedisInsight  [tunnel only]
│   └── dozzle/                ← Docker log viewer  [tunnel only]
├── config/
│   ├── supervisor/            ← Supervisor process configs (common/, fuelrod/, fees/, akilimo/)
│   ├── nginx/                 ← NGINX configs
│   ├── monitoring/            ← Grafana, Prometheus, Loki, Alloy
│   ├── beszel/                ← Beszel hub and host agent
│   ├── netdata/               ← Netdata host/container metrics
│   └── init/pgsql/            ← PostgreSQL init scripts (run on first container start)
├── log/
│   └── supervisor/            ← Bind-mounted log dirs (fees.prod/, fees.dev/)
├── stacks/databases/postgres/ ← postgres.conf
├── IMPROVEMENTS.md            ← reliability/security checklist
├── BACKLOG.md                 ← deferred work items
└── .backup-example            ← copy to .backup (backup credentials, gitignored)
```

EMQX deployment and WSS proxy routing are documented in
[`docs/mqtt.md`](docs/mqtt.md).

---

## Architecture

### Networks

| Network | Scope | Managed by |
|---|---|---|
| `dokploy-network` | External — inter-stack communication | Dokploy (created on install) |
| `internal` | Shared fixed-name network used by multiple stacks | Docker Compose |

Create `dokploy-network` manually when running without Dokploy:
```bash
docker network create dokploy-network
```

### Reverse Proxy & TLS

Public HTTP services are bound to host ports, usually on `127.0.0.1`. Each stack keeps the relevant routing snippets in `stacks/<name>/Caddyfile`; merge those snippets into the host Caddyfile. For Activepieces, `flow.munywele.co.ke` routes to `127.0.0.1:9710`.

Validate the merged host configuration before reloading it:

```bash
caddy validate --config /etc/caddy/Caddyfile
sudo caddy reload --config /etc/caddy/Caddyfile
```

### Bind Mount Paths

Bind mount paths in each compose file are **relative to that compose file's directory**. Shared config at the repo root is referenced with `../../`:

```yaml
# From stacks/fuelrod/docker-compose.yml:
- ../../config/supervisor/common:/etc/supervisor/conf.d   ✓
- ./config/supervisor/common:/etc/supervisor/conf.d       ✗  (resolves to stacks/fuelrod/config/...)
```

### PostgreSQL Initialisation

On first start (empty data volume) postgres runs `config/init/pgsql/` in sorted order:

| Script | Purpose |
|---|---|
| `00-extensions.sql` | Enables `uuid-ossp` and `pg_stat_statements` on the primary DB |
| `01-databases.sh` | Creates each database in `ADDITIONAL_DBS`; enables `uuid-ossp` on each |

### Cross-Stack Volumes

| Volume | Created by | Consumed by | Purpose |
|---|---|---|---|
| `uploads` | farm | — | Farm uploads |
| `fuelrod-uploads` | fuelrod | — | Fuelrod uploads |

Application services write logs to Docker stdout. Alloy discovers the selected Fuelrod, Fees, Fees Dev, and Akilimo containers through the Docker socket and forwards their logs to Loki. Netdata monitors host and Docker metrics independently.

---

## First-time Setup

```bash
# 1. Install Dokploy on the server (creates dokploy-network)
curl -sSL https://get.dokploy.com | sh

# 2. Copy and configure env files for each stack
for stack in databases cache activepieces automation monitoring fuelrod farm akilimo fees sonar metabase mail mqtt; do
  cp stacks/$stack/.env.example stacks/$stack/.env
done
# Edit each .env — replace all placeholder values and domains

# 3. Deploy stacks in order (see Deployment Order below)
```

---

## Deployment Order

```bash
# 1. External network required by the stacks
docker network create dokploy-network

# 2. Databases — must be first for PostgreSQL/MariaDB consumers
docker compose -f stacks/databases/docker-compose.yml up -d

# 3. Cache — separate Redis stack
docker compose -f stacks/cache/docker-compose.yml up -d

# 4. Automation / Activepieces
docker compose -f stacks/automation/docker-compose.yml up -d
docker compose -f stacks/activepieces/docker-compose.yml up -d

# 5. Monitoring, Beszel, Netdata, and applications
docker compose -f stacks/monitoring/docker-compose.yml up -d
docker compose -f stacks/beszel/docker-compose.yml up -d
docker compose -f stacks/netdata/docker-compose.yml up -d
docker compose -f stacks/fuelrod/docker-compose.yml up -d
docker compose -f stacks/farm/docker-compose.yml up -d
docker compose -f stacks/akilimo/docker-compose.yml up -d
docker compose -f stacks/fees/docker-compose.yml up -d
```

`activepieces` must exist in PostgreSQL before starting the Activepieces stack. Adding it to `ADDITIONAL_DBS` only creates it when `pgdata-main` is empty; on an existing database volume, create it explicitly with the shared PostgreSQL owner.

---

## Accessing Internal Tools via SSH Tunnel

**Adminer**, **RedisInsight**, and **Dozzle** are not exposed through Caddy. They bind only to `127.0.0.1` on the server and are accessed by forwarding a local port over SSH. This means no public URL or TLS certificate is needed.

### Bring up the stack

```bash
# On the server — deploy only when needed
docker compose -f stacks/db-tools/docker-compose.yml up -d   # Adminer + RedisInsight
docker compose -f stacks/dozzle/docker-compose.yml up -d     # Dozzle
```

### Open the SSH tunnel

Run this on your **local machine**:

```bash
# Adminer (postgres / mariadb GUI) — opens at http://localhost:8080
ssh -L 8080:localhost:8080 user@your-server.munywele.co.ke

# RedisInsight — opens at http://localhost:5540
ssh -L 5540:localhost:5540 user@your-server.munywele.co.ke

# Dozzle (container log viewer) — opens at http://localhost:9999
ssh -L 9999:localhost:9999 user@your-server.munywele.co.ke

# All three at once (single SSH session)
ssh -L 8080:localhost:8080 \
    -L 5540:localhost:5540 \
    -L 9999:localhost:9999 \
    user@your-server.munywele.co.ke
```

Open your browser while the SSH session is active. The tunnel closes when you exit the session.

### Take down when done

```bash
# On the server — never leave these running unattended
docker compose -f stacks/db-tools/docker-compose.yml down
docker compose -f stacks/dozzle/docker-compose.yml down
```

### Add to SSH config (optional convenience)

In `~/.ssh/config` on your local machine:

```
Host munywele-tools
    HostName your-server.munywele.co.ke
    User your-user
    LocalForward 8080 localhost:8080
    LocalForward 5540 localhost:5540
    LocalForward 9999 localhost:9999
```

Then just run `ssh munywele-tools` and all ports are forwarded automatically.

---

## Stack Setup Guides

Use the stack-local guide when configuring or troubleshooting a specific stack:

- [Activepieces](stacks/activepieces/README.md) — app/worker split, database setup, secrets, and worker token.
- [Beszel](stacks/beszel/README.md) — hub/agent setup, key/token generation, and access.
- [Netdata](stacks/netdata/README.md) — host metrics, privileged mounts, and Caddy access.
- [Monitoring](stacks/monitoring/README.md) — Grafana, Prometheus, Loki, Alloy, and log UI.

## Environment Files

Each stack has its own `.env` (gitignored) sourced from `.env.example`. Stacks sharing postgres credentials must use matching values — copy from `stacks/databases/.env`.

| Stack | Key variables |
|---|---|
| `databases` | `POSTGRES_USER/PASSWORD/DB`, `ADDITIONAL_DBS`, `MARIADB_*` |
| `cache` | `REDIS_PASSWORD`, `REDIS_DEV_PASSWORD` |
| `automation` | `POSTGRES_*` (must match databases), n8n runtime settings |
| `activepieces` | `AP_FRONTEND_URL`, `AP_ENCRYPTION_KEY`, `AP_JWT_SECRET`, `AP_WORKER_TOKEN`, `POSTGRES_*`, optional `REDIS_PASSWORD` |
| `monitoring` | `GRAFANA_*`, `LOKI_*` |
| `beszel` | `BESZEL_*`, host port `9625` |
| `netdata` | `NETDATA_*` |
| `fuelrod` | `FUELROD_TAG`, `FUELROD_DOMAIN`, `PORTAL_DOMAIN`, `GATEWAY_DOMAIN` |
| `farm` | `FARM_TAG`, `POSTGRES_*`, `JWT_SECRET`, `DEFAULT_PASSWORD` |
| `akilimo` | `AKILIMO_TAG`, `USE_UPTAKE_TAG`, `AKILIMO_DOMAIN`, `MARIADB_*` |
| `fees` | `SYNCER_TAG`, `FEES_PROD_DOMAIN`, `FEES_DEV_DOMAIN` |
| `sonar` | `SONAR_TAG`, `SONAR_DOMAIN`, `POSTGRES_*` |
| `metabase` | `METABASE_DOMAIN`, `POSTGRES_*` |
| `mail` | `MAILPIT_DOMAIN` |
| `db-tools` | `ADMINER_DEFAULT_SERVER`, `ADMINER_DESIGN` |
| `dozzle` | `DOZZLE_HOSTNAME` |

---

## Backup & Restore

The repository does not contain an active backup or migration toolchain. Use the database tooling appropriate for the deployment, and keep PostgreSQL/MariaDB backups outside Git. Never commit backup data or credentials.

---

## Caddy

Caddy is used as the host-level reverse proxy for WordPress-based stacks (Akilimo, and others as added). Each stack that uses Caddy keeps its own `Caddyfile` inside the stack directory (e.g. `stacks/akilimo/Caddyfile`). Copy the relevant blocks into the host's global Caddyfile.

### Common Commands

Validate config before applying (dry run):
```bash
caddy validate --config /etc/caddy/Caddyfile
```

Format / auto-indent the Caddyfile in place:
```bash
caddy fmt --overwrite /etc/caddy/Caddyfile
```

Reload config without downtime (no restart needed):
```bash
caddy reload --config /etc/caddy/Caddyfile
```

Restart the Caddy service (when reload is not enough):
```bash
sudo systemctl restart caddy
```

Stop / start:
```bash
sudo systemctl stop caddy
sudo systemctl start caddy
```

Enable Caddy to start on boot:
```bash
sudo systemctl enable caddy
```

Check service status and tail logs:
```bash
sudo systemctl status caddy
sudo journalctl -u caddy -f
```

Inspect the adapted (parsed) config:
```bash
caddy adapt --config /etc/caddy/Caddyfile --pretty
```

View Caddy version:
```bash
caddy version
```

Run Caddy in the foreground (useful for debugging):
```bash
sudo caddy run --config /etc/caddy/Caddyfile
```

Create the log directory if missing (fixes log writer errors on first run):
```bash
sudo mkdir -p /var/log/caddy
sudo chown -R caddy:caddy /var/log/caddy
```

### File Permissions for PHP-FPM Mounts

Directories are owned by `akilimo:akilimo`. The `www-data` user (PHP-FPM inside the container) is added to the `akilimo` group and gets write access via group permissions. The setgid bit (`s`) ensures files created by `www-data` inherit the `akilimo` group so the host user retains full control.

Run once on the host:
```bash
# Grant www-data group membership
sudo usermod -aG akilimo www-data
```

```bash
# Set ownership and permissions (drwxrwsr-x = 2775)
sudo chown -R akilimo:akilimo /data/extra_storage/services/akilimo
sudo chown -R akilimo:akilimo /data/extra_storage/services/portal
sudo chown -R akilimo:akilimo /data/extra_storage/services/new_akilimo
sudo chown -R akilimo:akilimo /data/extra_storage/services/agwise_site
sudo chmod -R 2775 /data/extra_storage/services/akilimo
sudo chmod -R 2775 /data/extra_storage/services/portal
sudo chmod -R 2775 /data/extra_storage/services/new_akilimo
```

### WordPress File Permissions

The `wordpress:php8.4-fpm` container runs as `www-data` (uid `33`). Because the WordPress directories are bind-mounted from the host, all files must be owned by uid `33` on the host — group membership tricks do not cross the container boundary.

**Fix `wp-content/upgrade` not writable:**
```bash
sudo mkdir -p /data/extra_storage/services/akilimo/wp-content/upgrade
sudo mkdir -p /data/extra_storage/services/portal/wp-content/upgrade
sudo mkdir -p /data/extra_storage/services/new_akilimo/wp-content/upgrade
sudo chown 33:33 /data/extra_storage/services/akilimo/wp-content/upgrade
sudo chown 33:33 /data/extra_storage/services/portal/wp-content/upgrade
sudo chown 33:33 /data/extra_storage/services/new_akilimo/wp-content/upgrade
```

**Fix core WordPress files not writable (full reset):**
```bash
# akilimo-site
sudo chown -R 33:33 /data/extra_storage/services/akilimo
sudo find /data/extra_storage/services/akilimo -type d -exec chmod 755 {} \;
sudo find /data/extra_storage/services/akilimo -type f -exec chmod 644 {} \;

# akilimo-portal
sudo chown -R 33:33 /data/extra_storage/services/portal
sudo find /data/extra_storage/services/portal -type d -exec chmod 755 {} \;
sudo find /data/extra_storage/services/portal -type f -exec chmod 644 {} \;

# new-akilimo
sudo chown -R 33:33 /data/extra_storage/services/new_akilimo
sudo find /data/extra_storage/services/new_akilimo -type d -exec chmod 755 {} \;
sudo find /data/extra_storage/services/new_akilimo -type f -exec chmod 644 {} \;

# agwise
sudo chown -R 33:33 /data/extra_storage/services/agwise
sudo find /data/extra_storage/services/agwise -type d -exec chmod 755 {} \;
sudo find /data/extra_storage/services/agwise -type f -exec chmod 644 {} \;

```

> **Note:** `755` on directories and `644` on files is the standard WordPress permission pattern. After running this, WordPress auto-updates, plugin installs, and theme uploads will work correctly.

---

### Stack Caddyfiles

Each stack keeps its own Caddyfile. Copy the relevant blocks into the host's global Caddyfile.

| Stack | Service | Caddyfile | Port |
|---|---|---|---|
| akilimo | `stacks/akilimo/Caddyfile` | `90xx` (PHP-FPM), `91xx` (API) |
| fuelrod | `stacks/fuelrod/Caddyfile` | `92xx` |
| farm | `stacks/farm/Caddyfile` | `93xx` |
| fees | `stacks/fees/Caddyfile` | `94xx` |
| use-uptake | `stacks/use-uptake/Caddyfile` | `95xx` |
| monitoring | Grafana | `stacks/monitoring/Caddyfile` | `9600` |
| netdata | Netdata | `stacks/netdata/Caddyfile` | `19999` |
| automation | n8n | `stacks/automation/Caddyfile` | `9700` |
| activepieces | Activepieces app | `stacks/activepieces/Caddyfile` | `9710` |

---

## Versioning & CI

- Commits to `main` trigger automatic SemVer tagging via `masgeek/github-tag-action`
- Commit message prefixes drive version bumps: `fix:` → patch, `feat:` → minor, `BREAKING CHANGE:` → major
- Renovate Bot manages Docker image tag updates
- PRs from non-owner actors are auto-approved by the `pr-automation` workflow
