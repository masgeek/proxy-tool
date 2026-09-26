# Fees Production

Production Fee Syncer runs independently from development. It publishes `127.0.0.1:9400` and uses the shared PostgreSQL, Redis, and MQTT services.

## Setup

```bash
cp .env.example .env
# Fill APP_KEY, database credentials, and MQTT credentials.
docker compose --env-file .env config --quiet
docker compose up -d
```

The public route is `fees.munywele.co.ke`; merge `Caddyfile` into the host Caddyfile. The container name remains `fee.prod`, so Alloy continues to label its logs as `fees`.
