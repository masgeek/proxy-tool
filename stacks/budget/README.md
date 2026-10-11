# Budget

Household budgeting and planning stack. Exactly one application runs at a time on `127.0.0.1:9720`, served publicly at `budget.munywele.co.ke`.

| App | Compose file | Database | API |
| --- | --- | --- | --- |
| Firefly III (default) | `services/firefly-iii.yml` | PostgreSQL + own Redis | REST |
| Yuvomi | `services/yuvomi.yml` | SQLite | REST + OpenAPI 3.1, MCP at `/mcp` |
| Actual Budget | `services/actual-budget.yml` | PostgreSQL | REST (sync server) |
| Econumo | `services/econumo.yml` | PostgreSQL | REST + MCP |
| ezBookkeeping | `services/ezbookkeeping.yml` | PostgreSQL | REST |

The main `docker-compose.yml` declares shared networks and volumes, plus one `budget` service that pulls its definition from a single file with `extends`. Changing that one `extends.file` value swaps the application.

## Setup

1. Copy `.env.example` to `.env` and fill in the secrets for the app you plan to run:

   ```bash
   cp stacks/budget/.env.example stacks/budget/.env
   ```

2. Create the database and role on the shared `postgres` service. For the default app:

   ```bash
   docker exec postgres createdb --username "$POSTGRES_USER" --owner "$POSTGRES_USER" firefly
   ```

   Add the database name to `.env` as `DB_DATABASE` and the role as `DB_USERNAME`.

3. Set `APP_KEY` to exactly 32 characters for Firefly III:

   ```bash
   head /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 32 && echo
   ```

4. Validate and start:

   ```bash
   docker compose --env-file stacks/budget/.env -f stacks/budget/docker-compose.yml config --quiet
   docker compose --env-file stacks/budget/.env -f stacks/budget/docker-compose.yml up -d budget
   ```

5. Open `https://budget.munywele.co.ke`. Firefly III registers an admin user on first visit; Yuvomi walks through first-run setup; Actual Budget creates the first budget in the browser.

## Switching application

Edit `extends.file` in `docker-compose.yml`:

```yaml
services:
  budget:
    extends:
      file: ./services/actual-budget.yml
      service: budget
```

Then recreate:

```bash
docker compose --env-file stacks/budget/.env -f stacks/budget/docker-compose.yml up -d budget
```

Only one service file may be referenced at a time. All apps bind `127.0.0.1:9720`, so they can never run simultaneously.

## Common variables

All service files read the same names, so switching apps changes only `extends.file` and the database block:

| Variable | Purpose |
| --- | --- |
| `APP_URL` | Public URL, used for links, callbacks and OAuth |
| `APP_ENV`, `APP_DEBUG` | Environment mode |
| `APP_KEY` | Application key (Firefly III `APP_KEY`, Actual Budget signing) |
| `DB_CONNECTION`, `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, `DB_PASSWORD` | PostgreSQL connection |
| `REDIS_*` | Firefly III cache, session and queue Redis (`redis-budget`; see `docs/redis-instances.md`) |
| `SESSION_SECRET`, `DB_ENCRYPTION_KEY` | Yuvomi session and optional SQLCipher key |
| `TZ` | Container timezone |
| `STACK_REVISION` | Deployment revision marker |

### Per-app settings

- **Yuvomi** — `SESSION_SECRET` is required; `DB_ENCRYPTION_KEY` enables SQLCipher with no recovery path if lost. State is one SQLite file at `DB_PATH` (default `/data/yuvomi.db`). `SESSION_SECURE=true` and `TRUST_PROXY=1` are required behind Caddy, otherwise logins and reset links break. The service runs as `user: "0:0"` because the image's non-root user cannot write to a freshly created named volume; if you prefer to keep the image user, chown the volumes once and remove that line:

  ```bash
  docker run --rm -v budget-data:/data -v budget-backups:/backups -v budget-modules:/app/modules -v budget-documents:/documents \
    busybox sh -c 'chown -R 1000:1000 /data /backups /app/modules /documents'
  ```

  A `SQLITE_CANTOPEN` error on start means exactly this: the container could not write `/data/yuvomi.db`.
- **Actual Budget** — set `ACTUAL_HTTPS=false` because Caddy terminates TLS. Import format: `DB_CONNECTION` is `postgres`, and the database name goes in `DB_NAME`.
- **Firefly III** — `TRUSTED_PROXIES=**` is needed behind Caddy, otherwise generated links use the wrong scheme. `APP_KEY` must be a long random string.
- **Econumo** — takes a single `DATABASE_URL` (`postgres://user:pass@host:5432/db?sslmode=disable`), not `DB_*`. The Compose file builds it by interpolation from `DB_USERNAME`, `DB_PASSWORD`, `DB_HOST`, `DB_PORT` and `ECONUMO_DB_NAME`, so you only change those; set `DATABASE_URL` explicitly to override. The `econumo-jwt` volume holds the JWT keypair and must be backed up with the database, otherwise every existing session token is invalidated after a restore.
- **ezBookkeeping** — configuration is `EBK_*`; `APP_KEY` maps to `EBK_SECURITY_SECRET_KEY`. The image runs as UID/GID 1000, so the service runs as root to keep the named volumes writable; the alternative is a one-time `chown 1000:1000` of `ezbookkeeping-storage` and `ezbookkeeping-logs`.

## Backups

PostgreSQL apps are covered by the repository's `db-backup/` tooling:

- Actual Budget: `actual_budget` database + `actual-budget-files` volume
- Firefly III: `firefly` database + `firefly-upload` volume
- Econumo: `econumo` database + `econumo-db` and `econumo-jwt` volumes
- ezBookkeeping: `ezbookkeeping` database + `ezbookkeeping-storage` and `ezbookkeeping-logs` volumes

Yuvomi keeps everything in `budget-data` (`/data/yuvomi.db`); a host-level file copy or `sqlite3 yuvomi.db ".backup"` is the backup, plus `budget-documents` if documents are stored locally.

## Routing

Caddy configuration lives in `config/caddy/snippets/domains/budget.caddy` and proxies `budget.munywele.co.ke` to `127.0.0.1:9720`.