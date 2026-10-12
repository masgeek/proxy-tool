# Budget

Household budgeting and planning stack. Exactly one application runs at a time on `127.0.0.1:9720`, served publicly at `budget.munywele.co.ke`.

| App | Compose file | Database | API |
| --- | --- | --- | --- |
| Firefly III (default) | `services/firefly-iii.yml` | PostgreSQL + own Redis | REST |
| Yuvomi | `services/yuvomi.yml` | SQLite | REST + OpenAPI 3.1, MCP at `/mcp` |
| Actual Budget | `services/actual-budget.yml` | PostgreSQL | REST (sync server) |
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
- **ezBookkeeping** — configuration is `EBK_*` following the shipped `conf/ezbookkeeping.ini`, where the object storage section is `storage` (so the variable is `EBK_STORAGE_TYPE`, and `EBK_OBJECT_STORAGE_TYPE` would be silently ignored). uploads and avatars go to the local `ezbookkeeping-storage` volume by default, with Alarik (`stacks/s3`) available as an opt-in: see the storage section below; `APP_KEY` maps to `EBK_SECURITY_SECRET_KEY`, and generate that with `openssl rand -base64 32`. The image resolves its config path from `EBK_CONF_PATH` and aborts with `open : no such file or directory` when that resolves to nothing, so `services/ezbookkeeping.ini` is mounted read-only into the container. That path is relative to the service file that declares the mount, not to the stack directory, so if you deploy from a different layout set `EZBOOKKEEPING_CONF` to an absolute path — Dokploy otherwise fails with `not a directory: Are you trying to mount a directory onto a file`; all operational values are overridden by environment variables, so no secret lives in that file. Two option names are easy to get wrong: `mode` belongs to the `global` section (omitting it aborts startup with `invalid server mode`) and the listen port is `http_port`, not `port`. `EBK_SERVER_ROOT_URL` is set explicitly so generated links carry no container port behind Caddy. The image runs as UID/GID 1000, so the service runs as root to keep the named volumes writable; the alternative is a one-time `chown 1000:1000` of `ezbookkeeping-storage`, `ezbookkeeping-logs` and `ezbookkeeping-data`. The `ezbookkeeping-data` volume is mounted even though this stack uses PostgreSQL, so falling back to sqlite3 by mistake cannot silently lose data.

## Backups

PostgreSQL apps are covered by the repository's `db-backup/` tooling:

- Actual Budget: `actual_budget` database + `actual-budget-files` volume
- Firefly III: `firefly` database + `firefly-upload` volume
- ezBookkeeping: `ezbookkeeping` database + `ezbookkeeping-storage`, `ezbookkeeping-logs` and `ezbookkeeping-data` volumes

Yuvomi keeps everything in `budget-data` (`/data/yuvomi.db`); a host-level file copy or `sqlite3 yuvomi.db ".backup"` is the backup, plus `budget-documents` if documents are stored locally.

## Routing

Caddy configuration lives in `config/caddy/snippets/domains/budget.caddy` and proxies `budget.munywele.co.ke` to `127.0.0.1:9720`.

## ezBookkeeping first user and API token

Create the first user without opening the browser, so the instance never needs
open registration:

```bash
# generate the encryption secret
docker compose --env-file stacks/budget/.env -f stacks/budget/docker-compose.yml   exec budget /ezbookkeeping/ezbookkeeping security gen-secret-key

# create the admin user
docker compose --env-file stacks/budget/.env -f stacks/budget/docker-compose.yml   exec budget /ezbookkeeping/ezbookkeeping userdata user-add   -n username -m you@example.com -i "Your Name" -p 'a-strong-password' -c KES
```

Afterwards set `EBK_USER_ENABLE_REGISTER=false` in `.env` and recreate.

Useful later, when the ingestion service exists:

```bash
# API token for the ingestion service
docker compose --env-file stacks/budget/.env -f stacks/budget/docker-compose.yml   exec budget /ezbookkeeping/ezbookkeeping userdata user-session-new   -n username --type api -e 0

# import and export from the CLI
... exec budget /ezbookkeeping/ezbookkeeping userdata transaction-import   -n username -f /ezbookkeeping/data/transactions.csv --type ezbookkeeping_csv
... exec budget /ezbookkeeping/ezbookkeeping userdata transaction-export   -n username -f /ezbookkeeping/data/export.csv --type csv
```

Enable `EBK_ENABLE_API_TOKEN=true` before minting a token, and set
`EBK_API_TOKEN_ALLOWED_REMOTE_IPS` to the Docker subnets so the token cannot be
used from the public internet. Transaction import and export also matter for the
SMS companion PRD: the CLI import path is the way historical data gets in, while
the REST API is the way the ingestion service writes going forward.

## ezBookkeeping object storage

Uploads and avatars are stored on the `ezbookkeeping-storage` volume by default.
One less service to run, and a backup of that volume is a file copy.

Alarik in `stacks/s3` is the alternative for anyone who wants files off the app
host. It is reachable in-network as `s3:8080` — not through the public host, which
would add latency and a TLS round trip for every file. Switching is one variable,
but it does **not** migrate files already stored, so treat it as a one-way move
unless you copy objects across first.

To switch:

1. Create the bucket. Either add it to `DEFAULT_BUCKETS` in `stacks/s3/.env`
   before starting that stack:

   ```
   DEFAULT_BUCKETS=ezbookkeeping
   ```

   or create it in the console at `https://s3-console.munywele.co.ke`.

2. Create an access key scoped to that bucket in the console, or set
   `DEFAULT_ACCESS_KEY` and `DEFAULT_SECRET_KEY` in `stacks/s3/.env` for apps to
   reuse. Prefer a per-app key: revoking one application then does not affect the
   others.

3. Put the storage settings in `stacks/budget/.env`:

   ```
   EBK_STORAGE_TYPE=s3
   EBK_STORAGE_S3_ACCESS_KEY_ID=...
   EBK_STORAGE_S3_SECRET_ACCESS_KEY=...
   ```

   The remaining `EBK_STORAGE_S3_*` values are already correct as commented
   defaults in `.env.example`.

4. Recreate the service and confirm files land in the bucket:

   ```bash
   docker compose --env-file stacks/budget/.env -f stacks/budget/docker-compose.yml up -d budget
   docker run --rm --network dokploy-network amazon/aws-cli      --endpoint-url http://s3:8080 s3 ls s3://ezbookkeeping
   ```

Two settings are load-bearing and easy to get wrong:

- **`EBK_STORAGE_S3_REGION` must equal `S3_REGION` in `stacks/s3`** (`us-east-1`).
  Alarik validates the region in the signature like real S3, so a mismatch fails
  every request.
- **`EBK_STORAGE_S3_USE_PATH_STYLE=true`** and `s3_endpoint` carries host and port
  only (`s3:8080`) — no scheme. TLS is the separate `EBK_STORAGE_S3_USE_SSL` flag,
  which stays false because this traffic never leaves the Docker network.

The `ezbookkeeping-storage` volume stays mounted either way, so reverting to
`EBK_STORAGE_TYPE=local_filesystem` needs no other change.
