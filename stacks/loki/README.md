# Loki

Loki runs as an independent stack while sharing the named `internal` Docker network with the monitoring stack.

## Setup

```bash
docker compose config --quiet
docker compose up -d
```

The API is available at `127.0.0.1:3100` and is consumed by Grafana Alloy and Prometheus on the shared `internal` network. Loki data is stored in the named `loki-data` volume.

## Verify

```bash
curl http://127.0.0.1:3100/ready
```
