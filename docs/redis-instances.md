# Redis Instances

Every Redis in this environment lives in `stacks/cache`. There are five
instances, grouped by role rather than one per application.

## Instances

| Hostname | Purpose | Password variable | Eviction |
|----------|---------|-------------------|----------|
| `cache` | shared application caches | `REDIS_PASSWORD` | `allkeys-lru` |
| `cache-dev` | development | `REDIS_DEV_PASSWORD` | default |
| `redis-invoice` | Invoice Ninja only | `REDIS_INVOICE_PASSWORD` | `allkeys-lru` |
| `redis-budget` | Firefly III only | `REDIS_BUDGET_PASSWORD` | `noeviction` |
| `redis-jobs` | queues and brokers only | `REDIS_JOBS_PASSWORD` | `noeviction` |

## Allocation

`cache` — shared caches and rate-limit stores, one logical database each:

| Stack | Database |
|-------|----------|
| fees-prod | 0 |
| shortener | 1 |
| akilimo | 2 |

`redis-jobs` — queues and brokers, one logical database each:

| Stack | Database |
|-------|----------|
| activepieces | 0 |
| kvuno (Celery broker and result backend) | 1 |
| fuelrod-api | 2 |

`redis-invoice` and `redis-budget` have a single application each, so database 0
is the only one in use.

## Why this grouping

- **Queues are never mixed with caches.** Anything holding a queue or broker uses
  `redis-jobs`, separate from every cache, so flushing a cache can never drop a
  job. `redis-jobs` runs `noeviction`: evicting a queued job loses work silently,
  so exceeding memory must fail loudly instead.
- **Anything mixing cache, session and queue gets its own instance.** Firefly III
  uses all three on one Redis, where an eviction policy tuned for the cache would
  otherwise discard session or job data. Invoice Ninja is treated the same way.
- **Everything else shares `cache` on separate databases with distinct key
  prefixes.** These are pure caches and rate-limit stores, so the failure mode of
  sharing is a cold cache, not lost data.
- Hostnames are prefixed because all instances join the same external
  `dokploy-network`, where a generic name like `redis` would resolve to several
  containers at once.

## Rules

- Add new workloads to `redis-jobs` if they hold a queue or broker, to `cache` if
  they only cache, and give an application its own instance when it mixes cache
  with session or queue data.
- Keep the container memory limit comfortably above `maxmemory` so Redis can free
  memory instead of being killed.
- Passwords are per instance, not global, so a compromised application cannot
  authenticate to an instance holding another application's queue.
- All instances run with `--appendonly yes`; queue and broker state must survive a
  restart.
- Deploy the cache stack before any application stack that points at it.

## Operating an instance

```bash
docker compose --env-file stacks/cache/.env -f stacks/cache/docker-compose.yml exec redis-jobs redis-cli -a "$REDIS_JOBS_PASSWORD" INFO keyspace
docker compose --env-file stacks/cache/.env -f stacks/cache/docker-compose.yml exec cache redis-cli -a "$REDIS_PASSWORD" INFO memory
```

`FLUSHDB` remains unsafe on `cache` and `redis-jobs` because they are shared.
Check the keyspace first, or target a specific logical database with `-n`.