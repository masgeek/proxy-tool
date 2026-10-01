# Activepieces

Activepieces runs as two services: `app` and `worker`. The app owns the UI/API and connects to PostgreSQL and Redis; the worker executes flows and connects only to the app.

## Setup

1. Ensure `databases` and `cache` are running.
2. Create the `activepieces` database if PostgreSQL already has data:

   ```bash
   docker exec postgres createdb --username "$POSTGRES_USER" \
     --owner "$POSTGRES_USER" activepieces
   ```

3. Copy and fill the environment file:

   ```bash
   cp .env.example .env
   ```

4. Generate secrets and the worker token:

   ```bash
   openssl rand -hex 16
   openssl rand -hex 32
   npx @activepieces/cli workers token
   ```

   Put the two generated values in `AP_ENCRYPTION_KEY` and `AP_JWT_SECRET`. Enter the same JWT secret when generating `AP_WORKER_TOKEN`, then copy the token into the `.env`.

5. Set `POSTGRES_USER` and `POSTGRES_PASSWORD` to the shared database credentials. Set `REDIS_PASSWORD` to the production cache password, or leave it empty when Redis authentication is disabled.

## Start and verify

```bash
docker compose --env-file .env config --quiet
docker compose up -d
curl http://127.0.0.1:9710/api/v1/health
```

The public route is `flow.munywele.co.ke`; merge `Caddyfile` into the host Caddyfile before exposing it publicly.

The worker has no published port. Keep `AP_ENCRYPTION_KEY` backed up: without it, stored connections cannot be decrypted.
