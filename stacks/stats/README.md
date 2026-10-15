# Tracearr stack — media-server monitoring

The stack directory is named `stats` for what it does, following the `budget`
convention for Firefly III. The application is Tracearr.

| | |
| --- | --- |
| Public URL | https://stat.munywele.co.ke |
| Host port | `127.0.0.1:8930` → container `3000` |
| Caddy | `config/caddy/snippets/domains/personal.caddy` |
| Upstream | https://github.com/connorgallopo/tracearr |

## Why the supervised image

Tracearr requires **TimescaleDB**. The shared `postgres` in `stacks/databases`
runs `postgis/postgis:17-3.5`, which does not provide the extension.

Building a custom image from `postgis/postgis` plus the TimescaleDB apt package
was considered and rejected:

- `shared_preload_libraries = 'timescaledb'` is **global**. It would change the
  behaviour of the instance serving akilimo, shirakalu, sonar, metabase, yamtrack
  and keycloak.
- pgbouncer runs in `transaction` mode, which TimescaleDB is not designed for.
- Upstream expects `max_locks_per_transaction=4096`, `max_connections=150`,
  `shm_size: 512mb` and `nofile 65536`. The shared instance runs
  `max_connections = 100` tuned for 4GB across six applications.
- It would add a custom image build pipeline to maintain on every PostgreSQL
  security patch.

The `supervised` tag bundles the app, TimescaleDB and Redis into one container,
which isolates all of that.

## Costs of this choice

Recorded so the trade is not forgotten later:

| | Supervised | Standard |
| --- | --- | --- |
| Containers | 1 | 3 |
| PostgreSQL | 15 | 18 (TimescaleDB HA) |
| Minimum RAM | **3GB** | ~1GB |
| Secrets | Auto-generated | Manual `.env` |
| Support status | Bare-metal only; **unsupported on VMs and nested container environments** | Documented, supported |

**Do not switch `TRACEARR_TAG` to `latest` expecting a smooth upgrade.** The
on-disk format differs between PostgreSQL 15 and 18, and PostgreSQL will refuse to
start against the old volume. Take a `pg_dump` first:

```bash
docker exec stats node apps/server/scripts/backup.ts
docker cp stats:/data/backup ./tracearr-backups
```

## Deploy

```bash
docker compose --env-file stacks/stats/.env -f stacks/stats/docker-compose.yml up -d stats
docker compose --env-file stacks/stats/.env -f stacks/stats/docker-compose.yml logs -f stats
```

Secrets are generated on first boot. The first start initialises PostgreSQL, so
allow a couple of minutes; the healthcheck `start_period` is 120s for that reason.

Open https://stat.munywele.co.ke and create the first account.

## Routing notes

The Caddy block sets `flush_interval -1` because Tracearr pushes live sessions
over SSE and Socket.IO. Caddy's default response buffering would hold events
until the upstream response completed, making the real-time view lag.

`TRUST_PROXY=true` is set because Tracearr decides whether to trust
`X-Forwarded-*` by hop count, and there is exactly one hop: this container behind
host Caddy.

## Volumes and backup

| Volume | Contents |
| --- | --- |
| `stats-postgres` | The database. The only copy of session history. |
| `stats-redis` | BullMQ job state. |
| `stats-data` | Poster image cache, application data and `/data/backup`. |

These are **not** covered by `db-backup`: that tooling is built against the shared
`databases` stack, and this database is deliberately not in it. Use Tracearr's own
backup, or add an explicit `pg_dump` job.

## Upgrading

```bash
docker compose --env-file stacks/stats/.env -f stacks/stats/docker-compose.yml pull
docker compose --env-file stacks/stats/.env -f stacks/stats/docker-compose.yml up -d stats
```

Back up first. The PostgreSQL major version in the supervised image has changed
between releases before.