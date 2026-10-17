# Invoice & Budgeting Stack — Deployment Checklist

Subtasks for provisioning and configuring the finance applications that back the
`stacks/budget` and `stacks/invoice` stacks against the shared PostgreSQL service.

Context for every item below:

- PostgreSQL is provided by `stacks/databases` and reachable on `dokploy-network` as hostname `postgres` (port 5432).
- Redis is provided by `stacks/cache` as `cache` (port 6379).
- Every app is published on `127.0.0.1:<port>` and exposed through Caddy only.
- `stacks/budget` runs Firefly III alone on `127.0.0.1:9720`.

## FrankenPHP applicability

FrankenPHP is a PHP application server and is relevant only to PHP apps. The
single application covered here is Firefly III; two alternatives were evaluated and
excluded — ExpenseOwl ships no authentication of its own and relies entirely on
proxy auth, and Econumo does not cover the intended use case.

| App | Runtime | FrankenPHP relevant |
| --- | --- | --- |
| Firefly III | PHP (Laravel) | Only if you build your own image; the official `fireflyiii/core` image already bundles nginx + PHP-FPM, so do not swap it |

If you later move Firefly III to FrankenPHP, use the `dunglas/frankenphp` base image,
mount the application at `/app`, and keep the container port at 8080 with Caddy still
terminating TLS in front. Everything else in this checklist is unchanged, because the
PostgreSQL connection is environment-driven either way.

---

Scope: Firefly III in `stacks/budget`, settled on as the single bookkeeping backend.


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

## Cross-stack final checks

- [ ] Every app is reachable only through Caddy; no port in the 9xxx range is bound to a public interface.
- [ ] `docker compose config --quiet` passes for the selected app in both stacks.
- [ ] `caddy validate --config /etc/caddy/Caddyfile` passes after any routing change.
- [ ] Backups verified by restoring one database dump into a scratch database.
- [ ] `docs/ports.md` and the stack README match the deployed port.