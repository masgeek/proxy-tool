# Invoice & Budgeting Stack — Deployment Checklist

Subtasks for provisioning and configuring the finance applications that back the
`stacks/budget` and `stacks/invoice` stacks against the shared PostgreSQL service.

Context for every item below:

- PostgreSQL is provided by `stacks/databases` and reachable on `dokploy-network` as hostname `postgres` (port 5432).
- Redis is provided by `stacks/cache` as `cache` (port 6379).
- Every app is published on `127.0.0.1:<port>` and exposed through Caddy only.
- All apps in `stacks/budget` are mutually exclusive: one is active at a time on `127.0.0.1:9720`, selected by the single `extends.file` value in `stacks/budget/docker-compose.yml`.

## FrankenPHP applicability

FrankenPHP is a PHP application server and is relevant only to PHP apps. Of the
applications covered here (ExpenseOwl was evaluated and excluded because it ships
no authentication of its own and relies entirely on proxy auth):

| App | Runtime | FrankenPHP relevant |
| --- | --- | --- |
| Firefly III | PHP (Laravel) | Only if you build your own image; the official `fireflyiii/core` image already bundles nginx + PHP-FPM, so do not swap it |
| Econumo | Go (single distroless binary) | No |
| ezBookkeeping | Go | No |

If you later move Firefly III to FrankenPHP, use the `dunglas/frankenphp` base image,
mount the application at `/app`, and keep the container port at 8080 with Caddy still
terminating TLS in front. Everything else in this checklist is unchanged, because the
PostgreSQL connection is environment-driven either way.

---

## 1. Firefly III

Stack file: `stacks/budget/services/firefly-iii.yml`

### Database provisioning and schema isolation

- [ ] Create the database and a dedicated role on the shared PostgreSQL service:
      `docker exec postgres psql -U "$POSTGRES_USER" -c "CREATE ROLE firefly LOGIN PASSWORD '…';"`
- [ ] Create the database owned by that role:
      `docker exec postgres psql -U "$POSTGRES_USER" -c "CREATE DATABASE firefly OWNER firefly;"`
- [ ] Grant only what the app needs (migrations require schema ownership, not superuser):
      `GRANT ALL ON SCHEMA public TO firefly;`
- [ ] Confirm `pg_hba.conf` allows password auth from the `dokploy-network` subnet for the `firefly` role.
- [ ] Add `firefly` to the `db-backup` database list so dumps run on schedule.

### Environment and application configuration

- [ ] Set `APP_KEY` to exactly 32 random characters:
      `head /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 32 && echo`
- [ ] Set `DB_CONNECTION=pgsql`, `DB_HOST=postgres`, `DB_PORT=5432`, `DB_DATABASE=firefly`, `DB_USERNAME=firefly`, `DB_PASSWORD=…`.
- [ ] Set `REDIS_HOST=cache`, `REDIS_PORT=6379`, `REDIS_PASSWORD=…`, `CACHE_DRIVER=redis`, `REDIS_CACHE_DB=1`.
- [ ] Set `APP_URL=https://budget.munywele.co.ke`.
- [ ] Set `TRUSTED_PROXIES=**` so generated links use `https` behind Caddy.
- [ ] Set `TZ=Africa/Nairobi`.
- [ ] Leave FrankenPHP alone for this image; only revisit if you build a custom image.

### Persistence and volumes

- [ ] Keep the `firefly-upload` volume mounted at `/var/www/html/storage/upload`.
- [ ] Back up both the `firefly` database and `firefly-upload`.

### Data ingestion and invoicing flow

- [ ] Register the first admin user at `https://budget.munywele.co.ke` on first visit.
- [ ] Under Options → Financial administrations → Actions → Edit, set the primary currency (for example KES) — the default is EUR and it is not env-driven.
- [ ] Under Options → Currencies, enable every currency you intend to use before creating asset accounts.
- [ ] Under Options → Preferences → Features, enable or disable the modules you want (budgets, bills, subscriptions, tags, webhooks).
- [ ] Configure a bank or import route: Firefly III has no bank sync of its own — either run the Data Importer against a CSV/OFX export or set up webhooks from your bank.
- [ ] Create asset accounts first, then categories, then recurring transactions; transactions cannot reference accounts that do not exist.
- [ ] If you use webhooks (`ALLOW_WEBHOOKS=true`), restrict the endpoints to the host Caddy or a LAN-only listener.

---

## 2. ezBookkeeping

Stack file: `stacks/budget/services/ezbookkeeping.yml`

### Database provisioning and schema isolation

- [ ] Create role and database:
      `docker exec postgres psql -U "$POSTGRES_USER" -c "CREATE ROLE ezbookkeeping LOGIN PASSWORD '…';"`
      `docker exec postgres psql -U "$POSTGRES_USER" -c "CREATE DATABASE ezbookkeeping OWNER ezbookkeeping;"`
- [ ] Grant schema privileges: `GRANT ALL ON SCHEMA public TO ezbookkeeping;`
- [ ] ezBookkeeping creates and migrates its own schema on first start; verify the tables land in `public` and not in a separate schema.
- [ ] Do not run it on SQLite for production — upstream explicitly recommends PostgreSQL or MySQL.

### Environment and application configuration

- [ ] Set `EBK_DATABASE_TYPE=postgres`.
- [ ] Set `EBK_DATABASE_HOST=postgres:5432` (host and port together, unlike Firefly III).
- [ ] Set `EBK_DATABASE_NAME=ezbookkeeping`, `EBK_DATABASE_USER=ezbookkeeping`, `EBK_DATABASE_PASSWD=…`.
- [ ] Set `EBK_SECURITY_SECRET_KEY` from `APP_KEY`; it protects tokens and must be stable across restarts, otherwise sessions break.
- [ ] Set `EBK_SERVER_DOMAIN=budget.munywele.co.ke` and `EBK_SERVER_PROTOCOL=https` so links and CSRF origins match Caddy.
- [ ] Set `EBK_LOG_MODE=file` (or `console` if you prefer Docker logs) and `TZ=Africa/Nairobi`.
- [ ] Enable gzip at the proxy; `EBK_SERVER_ENABLE_GZIP=true` only applies when serving directly.

### Persistence and volumes

- [ ] Mount `ezbookkeeping-storage` at `/ezbookkeeping/storage` — this holds user-uploaded receipt images.
- [ ] Mount `ezbookkeeping-logs` at `/ezbookkeeping/log`.
- [ ] Fix ownership if you run the image as its own user (UID/GID 1000):
      `chown -R 1000:1000` on both volumes.

### Data ingestion and invoicing flow

- [ ] Register the first user, then set the default currency and timezone under Settings.
- [ ] Create two-level accounts (asset/liability) before importing any transactions.
- [ ] Build the category tree you want before importing, so records map cleanly.
- [ ] Import existing history with the built-in importer (CSV, OFX, QIF, Firefly III export, Camt.053/MT940) and verify totals against your bank statement.
- [ ] Schedule recurring transactions for fixed bills and salaries.
- [ ] Enable 2FA for each user; the app also supports a PIN/WebAuthn application lock.

---

## 3. Econumo

Stack file: `stacks/budget/services/econumo.yml`

### Database provisioning and schema isolation

- [ ] Create role and database:
      `docker exec postgres psql -U "$POSTGRES_USER" -c "CREATE ROLE econumo LOGIN PASSWORD '…';"`
      `docker exec postgres psql -U "$POSTGRES_USER" -c "CREATE DATABASE econumo OWNER econumo;"`
- [ ] Grant schema privileges: `GRANT ALL ON SCHEMA public TO econumo;`
- [ ] Econumo runs migrations automatically on boot; no manual schema step.
- [ ] On PostgreSQL, use `pg_dump` for backups instead of the SQLite file-copy procedure.

### Environment and application configuration

- [ ] Set `DATABASE_URL=postgres://econumo:…@postgres:5432/econumo?sslmode=disable` — Econumo takes a single URL, not discrete `DB_*` parts.
- [ ] Percent-encode any password character that is special in a URL (`@` → `%40`, `:` → `%3A`, `/` → `%2F`, `#` → `%23`, `%` → `%25`).
- [ ] Set `BASE_URL=https://budget.munywele.co.ke` for correct links behind Caddy.
- [ ] Set `MAILER_DSN` for password recovery, for example
      `smtp://user:pass@smtp.example.com:587?encryption=tls&auth=true` (or use the shared Mailpit SMTP stack for testing).
- [ ] Set `TZ=Africa/Nairobi`; the app also has a per-user timezone setting.
- [ ] Register the first user, or run `user:create` from the container binary, and disable open registration afterwards if this is a single-family instance.

### Persistence and volumes

- [ ] Mount `econumo-jwt` at `/app/var/jwt` — it holds the JWT keypair. Losing it invalidates every issued token.
- [ ] Mount `econumo-db` at `/app/var/db` only if you keep SQLite as a fallback; with PostgreSQL in use the directory holds little, but keep it mounted so switching back does not lose data.
- [ ] Back up `econumo-jwt` together with the database — a database restore without the matching keypair still works, but all sessions are invalidated.

### Data ingestion and invoicing flow

- [ ] Create users, then invite a partner or family member with shared-account access.
- [ ] Create accounts per currency and set the default/base currency before entering data.
- [ ] Import the CSV export from your previous tool first, then reconcile opening balances.
- [ ] Set up budgets with folders and envelopes; available amounts are derived from them.
- [ ] Create classifications (categories) before recurring transactions reference them.
- [ ] Update currency rates via the container CLI (`/app/econumo`) or the scheduled job rather than by hand.
- [ ] Use the REST API or the MCP endpoint for automated tagging and transaction creation instead of scraping the UI.

---

## Cross-stack final checks

- [ ] Every app is reachable only through Caddy; no port in the 9xxx range is bound to a public interface.
- [ ] `docker compose config --quiet` passes for the selected app in both stacks.
- [ ] `caddy validate --config /etc/caddy/Caddyfile` passes after any routing change.
- [ ] Backups verified by restoring one database dump into a scratch database.
- [ ] `docs/ports.md` and the stack README match the deployed port.