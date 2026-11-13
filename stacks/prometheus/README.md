# Prometheus

Prometheus runs as an independent stack and shares the named `internal` network with Grafana, Loki, and the monitoring exporters.

## Setup

```bash
docker compose config --quiet
docker compose up -d
```

Prometheus is available at `127.0.0.1:9090`. Configuration and alert rules are mounted from `config/monitoring/prometheus.yml` and `config/monitoring/prometheus/rules/`. Metrics are retained in the named `prometheus-data` volume.
