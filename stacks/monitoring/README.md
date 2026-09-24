# Monitoring

This stack runs Grafana, Prometheus, Loki, and Alloy.

- Alloy reads selected Docker container logs and sends them to Loki.
- Loki stores logs and serves LogQL queries.
- Prometheus stores metrics scraped from Caddy, Loki, and Alloy.
- Grafana provides the log and metrics UI at `127.0.0.1:9600`.

## Setup

```bash
cp .env.example .env
# Set GRAFANA_ADMIN_USER and GRAFANA_ADMIN_PASSWORD.
docker compose --env-file .env config --quiet
docker compose up -d
```

The Caddy route is `logs.munywele.co.ke`; merge `Caddyfile` into the host Caddyfile. Grafana handles application authentication.

## Verify

```bash
curl http://127.0.0.1:3100/ready
curl http://127.0.0.1:9090/-/ready
curl http://127.0.0.1:9600/api/health
```

Loki retention is `48h` by default. Alloy drops health-check requests, favicon requests, and log lines over `32 KB` before ingestion.

Prometheus, Grafana, and Loki retain their named volumes. Do not add `--volumes` during normal teardown.
