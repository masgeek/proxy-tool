# Local Development — Monitoring Stack

The monitoring stack provides Grafana, Prometheus, Loki, and Alloy. Netdata is a separate stack for host/container metrics.

## Prerequisites

- Docker Engine with Docker Compose v2
- Ports 3100 and 19999 available locally if testing directly
- A stack `.env` with the Loki values from `stacks/monitoring/.env.example`

## Deploy the stack

```bash
cp stacks/monitoring/.env.example stacks/monitoring/.env
# Edit the copied file if the defaults need to be changed.
docker compose -f stacks/monitoring/docker-compose.yml config --quiet
docker compose -f stacks/monitoring/docker-compose.yml up -d
docker compose -f stacks/netdata/docker-compose.yml up -d
```

The stack requires the external `dokploy-network`; create it first when it does not exist:

```bash
docker network create dokploy-network
```

## Access services

| Service | Endpoint | Purpose |
|---------|----------|---------|
| Loki | `http://127.0.0.1:3100` | Log storage and LogQL API |
| Grafana | `http://127.0.0.1:9600` | Loki logs and Prometheus metrics UI |
| Alloy | internal only | Docker log collection and filtering |
| Netdata | `http://127.0.0.1:19999` | Host and Docker metrics UI |

Use Grafana at `http://127.0.0.1:9600` for LogQL browsing. `logcli` remains useful for scripted queries.

## Test log ingestion

Generate test entries from an application container:

```bash
docker exec fuelrod php artisan tinker --execute="logger()->warning('test fuelrod log line');"
docker exec fee.prod php artisan tinker --execute="logger()->warning('test fees log line');"
```

Wait a few seconds, then query from a machine that can reach Loki:

```bash
logcli --addr=http://127.0.0.1:3100 \
  query '{log_type="container", service_name="fees"}'
```

## Tear down

```bash
docker compose -f stacks/monitoring/docker-compose.yml down
docker compose -f stacks/netdata/docker-compose.yml down
```

This preserves the named Loki, Alloy, and Netdata volumes. Do not add `--volumes` unless permanent monitoring data should be deleted.

## Troubleshooting

### Alloy cannot discover containers

Confirm `/var/run/docker.sock` exists on the host and is mounted read-only into Alloy. Review the Alloy logs:

```bash
docker logs grafana-alloy
```

### Loki is unavailable

```bash
docker ps --filter name=loki
curl http://127.0.0.1:3100/ready
```

### Netdata has incomplete host metrics

Netdata requires host PID/network access, host `/proc` and `/sys`, the Docker socket, and `SYS_ADMIN`/`SYS_PTRACE`. Check the container configuration and host mounts if collectors are missing.
