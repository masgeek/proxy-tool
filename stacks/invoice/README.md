# Invoice

This stack runs Invoice Ninja using the shared `maria` database and `cache` Redis services. The application is published on `127.0.0.1:9705` and exposed through `invoice.munywele.co.ke`.

The previous Dolibarr Compose configuration is preserved as `docker-compose.dolibarr.yml` and is not deployed by this stack.

## Setup

1. Generate an application key:

   ```bash
   docker run --rm -it invoiceninja/invoiceninja-debian php artisan key:generate --show
   ```

2. Copy `.env.example` to `.env` and set `APP_KEY`, `DB_PASSWORD`, and `REDIS_PASSWORD`. Ensure the shared `maria` database has the `invoice` database/user and that the shared `cache` Redis password is set.
3. Optionally set `IN_USER_EMAIL` and `IN_PASSWORD` for first-start account creation, then remove them after setup.
4. Start the stack:

   ```bash
   docker compose --env-file .env config --quiet
   docker compose up -d
   ```

Open `https://invoice.munywele.co.ke` after the stack is healthy. Back up the shared MariaDB database and the `invoice-storage` volume before upgrades.