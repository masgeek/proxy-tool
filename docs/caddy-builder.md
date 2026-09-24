# Custom Caddy Build — Cache, Rate Limit & Log Transform

Adds response caching (Souin/Badger-backed), rate limiting, and log transforming to a stock Caddy install via `xcaddy`.

## Plugins included

| Module | Purpose |
|---|---|
| `github.com/caddyserver/cache-handler` | HTTP response caching (Souin) |
| `github.com/darkweak/storages/badger/caddy` | Persistent embedded cache storage for Souin (avoids the "default storage, dev only" warning) |
| `github.com/mholt/caddy-ratelimit` | Per-route / per-IP rate limiting |
| `github.com/caddyserver/transform-encoder` | Custom access log formatting |

---

## 1. Install xcaddy globally

```bash
go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
sudo mv ~/go/bin/xcaddy /usr/local/bin/xcaddy
xcaddy version
```

If `~/go/bin/xcaddy` doesn't exist, check `go env GOPATH` and look in `$GOPATH/bin` instead.

Alternative — prebuilt binary, no Go required:

```bash
curl -L https://github.com/caddyserver/xcaddy/releases/latest/download/xcaddy_$(curl -s https://api.github.com/repos/caddyserver/xcaddy/releases/latest | grep tag_name | cut -d'"' -f4 | tr -d v)_linux_amd64.tar.gz -o xcaddy.tar.gz
tar -xzf xcaddy.tar.gz xcaddy
sudo mv xcaddy /usr/local/bin/xcaddy
rm xcaddy.tar.gz
```

---

## 2. Build

### Bare metal

```bash
xcaddy build \
  --with github.com/caddyserver/cache-handler \
  --with github.com/darkweak/storages/badger/caddy \
  --with github.com/mholt/caddy-ratelimit \
  --with github.com/caddyserver/transform-encoder

sudo systemctl stop caddy
sudo mv ./caddy /usr/bin/caddy
sudo systemctl start caddy
```

### Docker (recommended — matches Dokploy-managed services)

```dockerfile
FROM caddy:builder AS builder

RUN xcaddy build \
    --with github.com/caddyserver/cache-handler \
    --with github.com/darkweak/storages/badger/caddy \
    --with github.com/mholt/caddy-ratelimit \
    --with github.com/caddyserver/transform-encoder

FROM caddy:latest
COPY --from=builder /usr/bin/caddy /usr/bin/caddy
```

Mount a persistent volume for the Badger cache path (e.g. `/data/caddy-cache`) so cache survives container restarts.

### Verify

```bash
caddy list-modules | grep -E "cache|ratelimit|transform|badger"
```

---

## 3. Config — route with cache + ratelimit (JSON)

```json
{
  "@id": "stats-api",
  "match": [
    { "host": ["stats.akilimo.org"] }
  ],
  "handle": [
    {
      "handler": "headers",
      "response": {
        "set": {
          "Content-Security-Policy": ["upgrade-insecure-requests"]
        }
      }
    },
    {
      "handler": "rate_limit",
      "zones": {
        "stats_zone": {
          "key": "{http.request.remote_ip}",
          "events": 100,
          "window": "1m"
        }
      }
    },
    {
      "handler": "cache",
      "config": {
        "ttl": "5m",
        "badger": {
          "path": "/data/caddy-cache",
          "configuration": {
            "syncWrites": true
          }
        }
      }
    },
    {
      "handler": "reverse_proxy",
      "upstreams": [
        { "dial": "127.0.0.1:9511" }
      ]
    }
  ],
  "terminal": true
}
```

**Order matters**: `headers` → `rate_limit` → `cache` → `reverse_proxy`. Cache must sit before `reverse_proxy` to intercept before proxying.

### Notes on caching behavior

- Only GET/HEAD requests with cacheable responses (2xx, no `Cache-Control: no-store`) are cached — POST uploads/attachments pass straight through untouched.
- If the upstream (`127.0.0.1:9511`) doesn't send `Cache-Control` headers, add `default_cache_control` under `config` to force the 5-minute TTL regardless of upstream headers:

```json
"config": {
  "ttl": "5m",
  "default_cache_control": "public, max-age=300",
  "badger": { "path": "/data/caddy-cache" }
}
```

### Notes on uploads/attachments

- Large request bodies stream through by default — Souin only buffers the response, not the request.
- If you need an explicit size cap, add before `reverse_proxy`:

```json
{
  "handler": "request_body",
  "max_size": 26214400
}
```

(25 MB — adjust as needed)

---

## 3b. Config — same route as a Caddyfile

Equivalent to the JSON block above, using the Caddyfile syntax exposed by these plugins:

```caddyfile
{
	order rate_limit before basicauth
	order cache before reverse_proxy
}

stats.akilimo.org {
	header Content-Security-Policy "upgrade-insecure-requests"

	rate_limit {
		zone stats_zone {
			key {remote_host}
			events 100
			window 1m
		}
	}

	cache {
		ttl 5m
		default_cache_control "public, max-age=300"
		badger {
			path /data/caddy-cache
			configuration {
				syncWrites true
			}
		}
	}

	reverse_proxy 127.0.0.1:9511
}
```

Notes:

- The global `order` block is required once per Caddyfile — it tells Caddy where `rate_limit` and `cache` slot into the directive execution order, since they're plugin-added directives, not built-ins.
- `default_cache_control` forces the 5-minute TTL even if the upstream doesn't send its own `Cache-Control` header.
- For an upload size cap, add `request_body { max_size 25MB }` inside the same block, before `reverse_proxy`.
- Redis instead of Badger:

```caddyfile
	cache {
		ttl 5m
		redis {
			configuration {
				Addrs 127.0.0.1:6379
			}
		}
	}
```

---

## 4. Troubleshooting

| Symptom | Fix |
|---|---|
| `You're running Souin with the default storage...` warning | Add a `storages` backend (Badger above, or Redis if already in your stack) — see config block |
| Uploads/attachments failing or truncated | Check `request_body.max_size` and upstream (PHP-FPM/app) body size limits |
| Rate limit false positives behind a proxy/LB | Confirm `{http.request.remote_ip}` reflects the real client IP, not the LB's — may need a trusted-proxy header module if fronted by another proxy |
| Cache serving stale data after upstream change | Reduce TTL for testing, or manually purge the Badger path / restart service |

---

## 5. Alternative — Redis storage instead of Badger

Only if Redis is already running in your stack for another service:

```bash
xcaddy build \
  --with github.com/caddyserver/cache-handler \
  --with github.com/darkweak/storages/redis/caddy \
  --with github.com/mholt/caddy-ratelimit \
  --with github.com/caddyserver/transform-encoder
```

```json
"config": {
  "ttl": "5m",
  "redis": {
    "configuration": {
      "Addrs": ["127.0.0.1:6379"]
    }
  }
}
```