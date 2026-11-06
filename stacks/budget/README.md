Household budgeting stack — Firefly III, published on `127.0.0.1:9720` and served
publicly at `budget.munywele.co.ke`.

The stack previously held several swappable bookkeeping applications behind a
Compose `extends` indirection. Firefly III is settled on, so the service is now
declared directly in `docker-compose.yml` and the alternatives are gone.

The stack runs its own self-contained PostgreSQL database (`db` service) and uses
a shared Redis instance (`redis-budget`) from `stacks/cache`.

## Setup

1. Copy `.env.example` to `.env` and fill in the secrets:

   ```bash
   cp stacks/budget/.env.example stacks/budget/.env
   ```

2. Generate `APP_KEY`. Firefly III requires exactly 32 characters:

   ```bash
   head /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 32 && echo
   ```

3. Deploy the cache stack first (for `redis-budget`), then start:

   ```bash
   docker compose --env-file stacks/cache/.env -f stacks/cache/docker-compose.yml up -d
   docker compose --env-file stacks/budget/.env -f stacks/budget/docker-compose.yml up -d
   ```

   The `db` service creates its own database (`firefly`) automatically on first start.

4. Open `https://budget.munywele.co.ke` and register the first admin user.

## Configuration notes

| Variable | Why it matters |
| --- | --- |
| `APP_KEY` | Must be exactly 32 characters, and changing it after first run invalidates encrypted data |
| `APP_URL` | Must match the public URL exactly, or generated links are wrong |
| `TRUSTED_PROXIES=**` | Required behind Caddy, otherwise Firefly builds `http` links for password reset and OAuth |
| `REDIS_HOST=redis-budget` | Dedicated instance from `stacks/cache`; Firefly mixes cache, session and queue, so it must not be shared (`docs/redis-instances.md`) |
| `DB_HOST=db` | Local `db` service in this stack; PostgreSQL data persists in `firefly_db_data` volume |
| `ALLOW_WEBHOOKS` | Set to `false` to reject webhook creation entirely |

## Purging the database (development)

Since the database is self-contained, purge everything and restart:

```bash
docker compose down -v
docker compose up -d
```

## First-run settings

Firefly's defaults are not the right ones for a single-currency household:

- **Currency** — EUR is hardcoded, not environment-driven. Set the administration's
  primary currency under Options → Financial administrations → Actions → Edit.
- **Enabled currencies** — only one is enabled by default. Enable KES and any other
  currency in use under Options → Currencies before creating asset accounts.
- **Assets and accounts** must exist before transactions can reference them.
- Firefly III has no bank sync of its own. Transactions arrive either through the
  Data Importer against a CSV/OFX export, through webhooks, or — planned — through
  the SMS ingestion service described in `docs/prd-sms-transactions-android.md`.

## Backups

- Database: the `firefly` database on the local `db` service, covered by the
  repository's `db-backup` tooling
- Uploads and attachments: the `firefly-upload` volume at
  `/var/www/html/storage/upload`

Both are required: the database references the uploaded files, and neither is
meaningful without the other.

## Development override

Use `docker-compose.dev.yml` for local development with a separate database
instance:

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

This adds an ephemeral `db` service for development that can be purged with
`down -v` without affecting production data.
