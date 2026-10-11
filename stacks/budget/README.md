# Budget

Household planning stack. The engine is [Yuvomi](https://yuvomi.cloud), a MIT-licensed self-hosted family planner covering tasks, calendar, meals and recipes, shopping, pantry, documents, budget, health, contacts and rewards.

Single container, no external database. Published on `127.0.0.1:9720` and served publicly at `budget.munywele.co.ke`.

## Setup

1. Copy `.env.example` to `.env` and generate the two secrets:

   ```bash
   cp .env.example .env
   openssl rand -hex 32   # SESSION_SECRET
   openssl rand -hex 32   # DB_ENCRYPTION_KEY (optional)
   ```

   Yuvomi refuses to start while `SESSION_SECRET` or `DB_ENCRYPTION_KEY` still contain their placeholder values.

2. Validate and start:

   ```bash
   docker compose --env-file stacks/budget/.env -f stacks/budget/docker-compose.yml config --quiet
   docker compose --env-file stacks/budget/.env -f stacks/budget/docker-compose.yml up -d budget
   ```

3. Open `https://budget.munywele.co.ke`. The first visit walks through creating the admin account.

## Encryption decision

`DB_ENCRYPTION_KEY` turns on SQLCipher for `/data/yuvomi.db`. There is no recovery path or back door: lose the key and the database is unreadable. Either

- set it and store the key with your other critical secrets, or
- leave it empty to keep the SQLite file readable

Decide this before the first deploy, because restoring an unencrypted backup into an encrypted installation (or the reverse) needs the key.

## HTTPS

The app is served through Caddy over TLS. This is required for web push notifications, which browsers refuse to deliver over plain HTTP on non-localhost origins.

## Outbound requests

Out of the box the only outbound call is a version check against the GitHub releases API. Enabling calendar (holidays), weather, currency rates, push channels, cloud document storage, or backup upload makes additional outbound requests.

## Modules

Schedule, waste collection and inventory are off by default upstream. Everything else can be switched off per household from the admin settings; disabled modules disappear from the menu.

## Backups

- `budget-data` — contains the SQLite database at `/data/yuvomi.db`; copying that one file is a full data export
- `budget-backups` — scheduled backup archives written by the app
- `budget-documents` — only needed when documents are stored locally rather than on WebDAV or Google Drive
- `budget-modules` — module assets

Yuvomi also has a built-in scheduled backup with optional WebDAV upload and restores in the browser, but a host-level file copy is still the durable backup.

## Routing

Caddy configuration lives in `config/caddy/snippets/domains/budget.caddy` and proxies `budget.munywele.co.ke` to `127.0.0.1:9720`.