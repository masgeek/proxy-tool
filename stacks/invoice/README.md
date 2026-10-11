# Invoice

This stack runs exactly one invoicing application at a time on `127.0.0.1:9705`, exposed through `invoice.munywele.co.ke`.

| Service | Compose file | API |
| --- | --- | --- |
| Invoice Ninja (default) | `services/invoice-ninja.yml` | REST |
| Dolibarr | `services/dolibarr.yml` | REST (`/api/index.php`) |
| Inkvoice | `services/inkvoice.yml` | REST |
| InvoiceShelf | `services/invoice-shelf.yml` | REST |

The main `docker-compose.yml` declares the shared networks, volumes, and a single `invoice` service that pulls its definition from one of the service files with `extends`. Changing that one `extends.file` value swaps the application; nothing else needs to change.

## Setup

1. Copy `.env.example` to `.env` and set the secrets for the application you plan to run.

   ```bash
   cp .env.example .env
   ```

   For Invoice Ninja set `APP_KEY`, `DB_PASSWORD`, and `REDIS_PASSWORD`, and ensure the shared `maria` service has the `invoice` database and user.

2. Validate and start:

   ```bash
   docker compose --env-file .env config --quiet
   docker compose up -d
   ```

   Generate `APP_KEY` with:

   ```bash
   docker run --rm -it invoiceninja/invoiceninja-debian php artisan key:generate --show
   ```

## Switching application

Edit the `extends.file` value in `docker-compose.yml`:

```yaml
services:
  invoice:
    extends:
      file: ./services/dolibarr.yml
      service: invoice
```

Then recreate the stack:

```bash
docker compose --env-file .env up -d
```

Only one service file may be referenced at a time. All three bind `127.0.0.1:9705`, so they can never run simultaneously.

## Dependencies

- Invoice Ninja uses the shared `maria` database and `cache` Redis service
- Dolibarr uses the shared `postgres` service with the `dolibarr` database and user
- Inkvoice stores all state in SQLite at `/app/data/invoice.db` on the `inkvoice-data` volume
- InvoiceShelf uses the shared `maria` service with the `invoiceshelf` database and user, plus its `invoiceshelf-storage` and `invoiceshelf-modules` volumes

## Backups

- Invoice Ninja: shared MariaDB `invoice` database and the `invoice-storage` volume
- Dolibarr: shared PostgreSQL `dolibarr` database and the `dolibarr-documents` and `dolibarr-custom` volumes
- Inkvoice: the `inkvoice-data` volume (or a copy of `/app/data/invoice.db`)
- InvoiceShelf: shared MariaDB `invoiceshelf` database and the `invoiceshelf-storage` and `invoiceshelf-modules` volumes