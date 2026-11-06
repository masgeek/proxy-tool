# Handover — Budget, KVuno, Sentry Stack Changes

## Budget Stack (`stacks/budget/`)

### Self-contained database
- Added `db` service (PostgreSQL `16-alpine`) to `docker-compose.yml` with `firefly_db_data` volume
- Production stack now uses its own local DB (hostname `db`)
- Redis shares the `cache` instance from `stacks/cache` (db 4) — see "Redis consolidation" below
- Volumes kept as-is (`firefly_upload`, `firefly_db_data`)
- Removed `internal` network (only `dokploy-network` external used)

### Development override (`docker-compose.dev.yml`)
- Uses `include` pattern to pull base service definition from `services/firefly-iii.yml`
- Dev stack adds its own local `db` service (`postgres:17-alpine`) with `PGDATA=/var/lib/postgresql/data/pgdata`
- Dev `budget` service connects to `db` host instead of shared `postgres`
- Overrides `APP_ENV: development`, `APP_DEBUG: "true"`
- Production `docker-compose.yml` now includes `services/firefly-iii.yml` for the base `budget` service definition

### Environment variables
- All env values moved to `environment:` section with `${VAR:-default}` interpolation
- Removed `env_file: services/.env` references

### Usage
```bash
# Production (local budget db, shared cache instance)
docker compose up -d

# Development (local postgres db, shared cache instance)
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

### Purging the database
Since the DB is now self-contained:
```bash
docker compose down -v db   # or full down -v to reset everything
docker compose up -d
```

### Removed
- `stacks/budget/purge-db.sh` (no longer needed — `down -v` handles it)
- `stacks/budget/services/.env` and `.env.dev` (no longer referenced)


## KVuno Stack (`stacks/kvuno/`)

### Port corrections
- API: `127.0.0.1:9800:80` (was correct)
- Web: changed from `127.0.0.1:5001:80` → `127.0.0.1:9801:80` (aligned to 9xxx range)
- Fixed `depends_on` in `web` service: `api` → `kvuno` (actual service name is `kvuno`, not `api`)

### Caddy routes (`stacks/kvuno/Caddyfile`)
- API: `kvuno.agwise.org` → `127.0.0.1:9800`
- Web: `kvuno-ui.agwise.org`, `kvuno-ui.akilimo.org` → `127.0.0.1:9801`
- Domain changed from `web.kvuno.agwise.org` → `kvuno-ui.agwise.org` (hyphen separator, shorter)

### Caddy snippet
- Centralized in `config/caddy/snippets/domains/agwise.caddy` with both `kvuno` and `kvuno-ui` blocks


## Sentry Stack (`stacks/sentry/`) — New Stack

### Structure
- `stacks/sentry/docker-compose.yml` — GlitchTip service
- `stacks/sentry/.env.example` — env vars (sensitive values required via `:?`)
- `config/caddy/snippets/domains/sentry.caddy` — dedicated Caddy snippet (not per-stack Caddyfile)
- Removed standalone `stacks/sentry/Caddyfile` to avoid sprawl

### Configuration
- Uses shared PostgreSQL (`databases` stack, hostname `postgres`)
- Dedicated Redis (`cache` stack, `redis-sentry`) with `noeviction` — Sentry mixes cache/session/queue
- Domains: `sentry.akilimo.org`, `sentry.munywele.co.ke`
- Mailgun SMTP support (`MAILGUN_API_KEY`, `MAILGUN_SENDER_DOMAIN`)
- Port: `127.0.0.1:9805:8000`

### Databases stack
- Added `sentry` to `ADDITIONAL_DBS` in `stacks/databases/.env.example`

### Pending: Docs review
- Some `SENTRY_*` env vars were removed pending verification against `https://glitchtip.com/documentation/install#configuration`
- Kept `SERVER_EMAIL` (doesn't start with `SENTRY`)

### Mailgun SMTP setup
Add to `.env`:
```bash
EMAIL_URL=smtp://default:YOUR_MAILGUN_SMTP_PASSWORD@smtp.mailgun.org:587
DEFAULT_FROM_EMAIL=noreply@your-domain.com
MAILGUN_API_KEY=your-mailgun-api-key
MAILGUN_SENDER_DOMAIN=your-domain.com
```

### Sensitive values
Required via `:?` syntax — stack will fail to start if missing:
- `DJANGO_SECRET_KEY`
- `DB_PASSWORD`


## Cache Stack (`stacks/cache/`) — Modified

### New Redis instance
- Added `redis-sentry` service (`redis:8`, `noeviction`, `appendonly yes`)
- Volume: `redis-sentry-data`
- Memory limit: 768m
- Env vars in `stacks/cache/.env.example`: `REDIS_SENTRY_PASSWORD`, `REDIS_SENTRY_MAXMEMORY`
- GlitchTip mixes cache/session/queue (Celery broker) on one Redis URL, so it keeps its own instance

### Redis consolidation (6 → 4 instances)
- `redis-invoice` and `redis-budget` removed, along with their volumes and
  `REDIS_INVOICE_*`/`REDIS_BUDGET_*` env vars
- Invoice Ninja and Firefly III (budget) were given their own Redis instances
  under the "mixes cache/session/queue" rule, but neither actually configures
  Redis for anything but caching (no `QUEUE_CONNECTION`/`SESSION_DRIVER=redis`)
- Both now share the `cache` instance on their own logical database:
  Invoice Ninja → db 3, Firefly III (budget) → db 4
- Updated: `stacks/invoice/services/invoice-ninja.yml`, `stacks/invoice/.env.example`,
  `stacks/invoice/README.md`, `stacks/budget/services/firefly-iii.yml`,
  `stacks/budget/.env.example`, `stacks/budget/README.md`, `stacks/budget/docker-compose.yml`
- `redis-sentry` and `redis-jobs` are unaffected; `cache-dev` intentionally left
  standalone rather than merged, to keep dev data out of the production cache
- `REDIS_PASSWORD` for Invoice Ninja and Firefly III must now match `cache`'s
  `REDIS_PASSWORD` in `stacks/cache/.env`, not their old dedicated passwords

## Databases Stack (`stacks/databases/`) — Modified

- Added `sentry` to `ADDITIONAL_DBS` list

## Documentation updated
- `README.md` — repository layout, deployment order, stack table, Caddy port table
- `docs/ports.md` — added kvuno web (9801) and sentry (9805), fixed kvuno api container port (80 not 5000)
- `docs/redis-instances.md` — added `redis-sentry` row, then removed `redis-invoice`/`redis-budget` rows and updated instance count to four

## All pending verifications
- GlitchTip env var names need cross-check against `https://glitchtip.com/documentation/install#configuration`
- Remove any `SENTRY_*` vars not in the official docs (already done once; re-verify before production deploy)
