# Redis Database Registry

The `stacks/cache` service (hostname `cache` on `dokploy-network`) is shared by
several application stacks. Redis logical databases are isolated from each other,
so every stack must pick its own index. Two stacks on the same index only stay
safe when their key namespaces cannot overlap, which is rarely something to rely
on — Laravel and PHP apps default to unprefixed keys, so a `FLUSHDB` or a
colliding key can wipe another application's cache.

Default Redis databases: **0**–**15**.

## Allocation

Every stack that uses the shared `cache` service gets its own index. Index 0 is
kept empty so that an application which forgets to configure a database lands
somewhere visibly unused rather than on top of a live application.

| Index | Stack | Service | Variable |
|-------|-------|---------|----------|
| 0 | *reserved* | — | Left empty on purpose |
| 1 | budget | Firefly III (default app) | `REDIS_CACHE_DB=1` |
| 2 | invoice | invoice (Invoice Ninja) | `REDIS_DB=2` |
| 3 | fees-prod | api | `REDIS_DB=3` |
| 4 | shortener | shortener | `REDIS_DB=4` |
| 5 | kvuno | api | Celery broker and result backend, `redis://cache:6379/5` |
| 6 | activepieces | app | `AP_REDIS_DB=6` |
| named `fuelrod` | fuelrod-api | api | Laravel connection name `REDIS_QUEUE=fuelrod` |

Stacks that do not use the shared `cache` service at all:

| Stack | Redis host | Note |
|-------|-----------|------|
| fees-dev | `cache-dev` | Separate cache instance for development |
| akilimo | `redis` | Points at a host named `redis`, verify it resolves on `dokploy-network` |

## Rules

- Allocate the next free index when adding a stack; never reuse an index without
  checking this table and the key namespace of both occupants.
- Keep per-application variables (`REDIS_DB`, `REDIS_CACHE_DB`, `AP_REDIS_DB`) in the
  stack's `.env` so the allocation is visible without reading the Compose file.
- A Laravel stack that uses Redis for cache, session and queue should set all
  three connections to its allocated index, not just the cache one.
- Never run `FLUSHDB` against the shared instance without first confirming which
  index is targeted; `redis-cli -n <index> DBSIZE` shows what lives there.
- Changing an index does not migrate data: the old keys stay in the previous index
  until it is cleaned deliberately. Old cache and rate-limit keys are safe to
  delete; a queue or broker index is not, so drain it first.