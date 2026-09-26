# GeoServer and Stats API

This stack runs GeoServer on `127.0.0.1:9510` and the Stats API on `127.0.0.1:9511`. The public routes are `geo.akilimo.org` and `stats.akilimo.org`.

## Scheduled maintenance

Use two Server Jobs in the scheduler with timezone `UTC`:

| Job | Cron (UTC) | Kenya time | Script/command |
|---|---|---|---|
| Stop GeoServer and Stats API | `0 13 * * *` | 16:00 daily | `docker stop stats-api geoserver 2>/dev/null || true` |
| Start GeoServer and Stats API | `0 5 * * 1-5` | 08:00 | `docker start geoserver stats-api 2>/dev/null || true` |

The container names are defined in `docker-compose.yml` as `geoserver` and `stats-api`. Verify them on the host with:

```bash
docker ps --format '{{.Names}}'
```

GeoServer can take a few minutes to become ready after starting because of JVM warm-up and data-store reconnects. If Stats API depends on GeoServer, stagger the combined start job with a wait:

```bash
docker start geoserver 2>/dev/null || true
sleep 120
docker start stats-api 2>/dev/null || true
```

Use `55 4 * * 1-5` for a 07:55 Kenya start.

## Command examples

Stop both services safely:

```bash
docker stop stats-api geoserver 2>/dev/null || true
```

Start both services safely:

```bash
docker start geoserver stats-api 2>/dev/null || true
```

Start with a GeoServer warm-up delay:

```bash
docker start geoserver 2>/dev/null || true
sleep 120
docker start stats-api 2>/dev/null || true
```

Check current state:

```bash
docker ps -a --filter name=geoserver --filter name=stats-api \
  --format 'table {{.Names}}\t{{.Status}}'
```

