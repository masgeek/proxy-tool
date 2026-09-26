# Fees Development

Development Fee Syncer runs independently from production. It publishes `127.0.0.1:9401` and uses the shared PostgreSQL, development Redis, and MQTT services.

## Setup

```bash
cp .env.example .env
# Fill APP_KEY and development database credentials.
docker compose --env-file .env config --quiet
docker compose up -d
```

The public route is `fees-dev.munywele.co.ke`; merge `Caddyfile` into the host Caddyfile. The container name remains `fee.dev`, so Alloy continues to label its logs as `fees-dev`.
