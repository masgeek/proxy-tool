# Invoice

This stack runs Dolibarr as the invoicing and ERP application. It is published on `127.0.0.1:9705` and exposed publicly through `invoice.munywele.co.ke`.

## Setup

1. Create a PostgreSQL database and user in the shared `databases` stack:

   ```sql
   CREATE DATABASE invoice;
   CREATE USER dolibarr WITH PASSWORD 'change_me';
   GRANT ALL PRIVILEGES ON DATABASE invoice TO dolibarr;
   ```

2. Copy `.env.example` to `.env` and set `DB_PASSWORD`, `ADMIN_PASSWORD`, and the company details.
3. Keep `INSTALL_AUTO=0`; the official image requires manual PostgreSQL installation.
4. Start the stack:

   ```bash
   docker compose --env-file .env config --quiet
   docker compose up -d
   ```

5. Open `https://invoice.munywele.co.ke/install` and complete the PostgreSQL installation.
6. Create the install lock so the container starts normally:

   ```bash
   docker exec invoice touch /var/www/documents/install.lock
   docker exec invoice ls -l /var/www/documents/install.lock
   ```

   The lock is stored in the persistent `dolibarr-documents` volume and survives restarts. The Compose service name is also `invoice`:

   ```bash
   docker compose exec invoice touch /var/www/documents/install.lock
   ```

The image follows the official tag model: use `latest`, `develop`, or a pinned `x.y.z` release in `DOLIBARR_TAG`.

If external module installation reports that it cannot write to `/var/www/html/custom`, fix the persistent volume ownership once:

```bash
docker exec -u root invoice chown -R www-data:www-data /var/www/html/custom
```

Back up the PostgreSQL database and the `dolibarr-documents` and `dolibarr-custom` volumes before upgrades.