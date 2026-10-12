# Baserow

Operational database: a grid UI over PostgreSQL, published on `127.0.0.1:9730`
and served publicly at `baserow.munywele.co.ke`.

What this is **not**: a place to keep financial records. Firefly III in
`stacks/budget` remains the system of record for money. Baserow holds the
read-mostly operational material that is currently scattered across this
repository's Markdown.

## What it is for here

1. **Stack and asset inventory** — one row per running service: stack, host port,
   container port, domain, database, Redis instance. Today that lives in
   `README.md` and `docs/ports.md` and drifts every time a port changes.
2. **Backup and restore drill log** — which databases were dumped, when, and
   whether a restore was actually verified.
3. **Domain and certificate register** — expiry dates and renewal owners, paired
   with the existing blackbox exporter rather than relying on manual tracking.
4. **Later, possibly: the review UI for SMS-captured transactions.** The ingestion
   service in `docs/prd-sms-transactions-android.md` specifies a review queue with
   approve, reject and edit actions. Baserow could *be* that queue instead of a
   bespoke interface. Only worth doing if that work actually starts.

## Components

Five containers, which is more than most stacks here:

| Container | Role |
| --- | --- |
| `baserow-backend` | Django REST and GraphQL API |
| `baserow-web-frontend` | Vue frontend, the only published port |
| `baserow-celery-worker` | async jobs |
| `baserow-celery-exportworker` | imports, exports, file processing |
| `baserow-celery-beat-worker` | scheduled jobs |

Budget roughly 2.5 GB across all five, plus the shared database. This is the
heaviest stack in the repository — if memory is tight, run the SQLite-free
PostgreSQL configuration and drop the beat worker's limits to 256m first.

## Why the split images

`baserow/baserow` bundles its own Caddy and will attempt to obtain certificates
for its own domain. The host Caddy already owns TLS for every domain in this
repository, so a second automatic ACME client is a conflict waiting to happen.
The split `baserow/backend` plus `baserow/web-frontend` images let the host proxy
reach exactly one container, and the backend's internal Caddy is a plain-HTTP hop
only.

## Setup

1. Copy `.env.example` to `.env` and set `SECRET_KEY` and `DB_PASSWORD`. Generate
   the key with `openssl rand -base64 48` and keep it: losing it logs everyone out
   and invalidates outstanding password-reset links.

2. Create the database on the shared `postgres` service:

   ```bash
   docker exec postgres createdb --username "$POSTGRES_USER" --owner "$POSTGRES_USER" baserow
   ```

3. Deploy the cache stack first, and set `REDIS_PASSWORD` here to match
   `REDIS_JOBS_PASSWORD` there. Baserow uses the `redis-jobs` instance on database
   3 — it is a Celery queue, so that instance runs `noeviction` and must never be
   flushed. See `docs/redis-instances.md`.

4. Optionally create the first account headlessly, by setting `BASEROW_INSTALL_JSON`
   to a single-line JSON object before the first start:

   ```json
   {"baserowadmin": {"email":"you@example.com","password":"<strong>","name":"Admin"}}
   ```

   The value is ignored once an account exists, so it can be cleared from `.env`
   afterwards. Leaving it empty is fine too — the first visit walks through
   creating an account.

5. Start and validate:

   ```bash
   docker compose --env-file stacks/baserow/.env -f stacks/baserow/docker-compose.yml config --quiet
   docker compose --env-file stacks/baserow/.env -f stacks/baserow/docker-compose.yml up -d
   ```

6. Open `https://baserow.munywele.co.ke`.

## Loading the inventory

`inventory-template.csv` is a starter file for the first table. In Baserow, create
a database named `infrastructure`, add a table `stacks` with the columns from the
header row, then import the CSV (table options → import data). Replace the sample
rows with the full set from `docs/ports.md`, and add a `Caddyfile` value or a note
where a stack has no routing.

Keeping it in Baserow does not replace `docs/ports.md` — that file is what
deployment tooling reads. Baserow is the working view; the docs stay authoritative.

## User files

Uploads land on the `baserow-media` volume by default. Alarik in `stacks/s3` is
configured but commented out in `docker-compose.yml`: uncomment the `AWS_*` block
and set the bucket, region and endpoint. Alarik is path-style and its region must
match `S3_REGION` in `stacks/s3`, or signatures are rejected.

Switching storage backends does not migrate existing files, so treat it as a
one-way move unless objects are copied across.

## Licensing

Core Baserow is MIT. **Premium and enterprise features are paid** — forms
collection, some sharing controls, advanced automation and the enterprise sync.
Everything described above stays in the core; if a feature you need turns out to be
premium, that is the point to stop and reassess rather than buy a licence for a
side experiment.

## Backups

- Database: the `baserow` database on the shared `postgres` service, covered by the
  repository's `db-backup` tooling
- Attachments: the `baserow-media` volume, or the Alarik bucket if that is enabled

The application-generated secrets in `/baserow/media` include the JWT signing key.
Back the volume up before a version upgrade, not only after.
