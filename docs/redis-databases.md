# Redis Database Registry

The `stacks/cache` service (hostname `cache` on `dokploy-network`) is shared by
several application stacks. Redis logical databases are isolated from each other,
so every stack must pick its own index. Two stacks on the same index only stay
safe when their key namespaces cannot overlap, which is rarely something to rely
on — Laravel and PHP apps default to unprefixed keys, so a `FLUSHDB` or a
colliding key can wipe another application's cache.

Default Redis databases: **0**–**15**.

## Allocation

| Index | Stack | Service | Notes |
|-------|-------|---------|-------|
| 0 | fees-prod | api | `REDIS_DB=0` |
| 0 | shortener | shortener | `REDIS_DB=0`, Kutt key prefix |
| 0 | activepieces | app | no database configured, Activepieces key prefix |
| 1 | budget | Firefly III (default app) | `REDIS_CACHE_DB=1` |
| 2 | invoice | invoice | `REDIS_DB=2` |
| 5 | kvuno | api | Celery broker and result backend, `redis://cache:6379/5` |
| named `fuelrod` | fuelrod-api | api | Laravel `REDIS_QUEUE=fuelrod` |

Stacks that do not use the shared `cache` service at all:

| Stack | Redis host | Note |
|-------|-----------|------|
| fees-dev | `cache-dev` | Separate cache instance for development |
| akilimo | `redis` | Points at a host named `redis`, verify it resolves on `dokploy-network` |

## Rules

- Allocate the next free index when adding a stack; never reuse an index without
  checking this table and the key namespace of both occupants.
- Keep per-application variables (`REDIS_DB`, `REDIS_CACHE_DB`) in the stack's
  `.env` so the allocation is visible without reading the Compose file.
- A Laravel stack that uses Redis for cache, session and queue should set all
  three connections to its allocated index, not just the cache one.
- Never run `FLUSHDB` against the shared instance without first confirming which
  index is targeted; `redis-cli -n <index> DBSIZE` shows what lives there.