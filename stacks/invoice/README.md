# Invoice

This stack runs Dolibarr as the invoicing and ERP application. It is published on `127.0.0.1:9705` and exposed publicly through `invoice.munywele.co.ke`.

## Setup

1. Create a PostgreSQL database and user in the shared `databases` stack:

   ```sql
   CREATE DATABASE invoice;
   CREATE USER dolibarr WITH PASSWORD 'change_me';
   GRANT ALL PRIVILEGES ON DATABASE invoice TO dolibarr;
   ```

2. Copy `.env.example` to `.env` and set `DB_PASSWORD`.
3. Set `ADMIN_PASSWORD` for the initial Dolibarr administrator account.
4. Start the stack:

   ```bash
   docker compose --env-file .env config --quiet
   docker compose up -d
   ```

Open `https://invoice.munywele.co.ke` after the application is healthy. Back up the PostgreSQL database and the `dolibarr-documents` and `dolibarr-var` volumes before upgrades.