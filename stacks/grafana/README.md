# Grafana

Grafana runs as an independent stack and shares the named `internal` network with Prometheus, Loki, and the monitoring exporters.

## Setup

```bash
cp .env.example .env
# Set GRAFANA_ADMIN_USER and GRAFANA_ADMIN_PASSWORD.
docker compose --env-file .env config --quiet
docker compose up -d
```

Grafana is available at `127.0.0.1:9600`. Dashboards and the Prometheus datasource are provisioned from `config/monitoring/grafana/`.
