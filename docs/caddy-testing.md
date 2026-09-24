# Testing the Production Caddyfile

Run these checks on the production host before restarting Caddy. Do not overwrite the live configuration until both validation commands pass.

## 1. Verify the compiled modules

```bash
caddy list-modules | grep -E 'cache|rate_limit|transform|badger'
```

The output must include `http.handlers.cache`. The current configuration also declares the `rate_limit` and `cache` directive order, so the compiled Caddy build must include those plugin modules.

## 2. Validate the repository file

```bash
caddy adapt --config config/caddy/Caddyfile --adapter caddyfile >/tmp/caddy-adapted.json
caddy validate --config config/caddy/Caddyfile --adapter caddyfile
```

Both commands must exit successfully. Keep `/tmp/caddy-adapted.json` when troubleshooting because it shows the handlers Caddy will actually run.

If Caddy reports `File to import not found` for a named snippet, use a relative file import such as `import ../headers/security-headers.caddy`; named snippets are not shared across separately imported files. If it reports that a plugin directive was parsed as a site address, move `order ...` directives inside the global `{}` options block.

## 3. Verify the Docker bridge address

The aggregate Caddyfile binds the admin API to `172.17.0.1:2019`. Confirm that this is the host-side Docker bridge address:

```bash
docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}'
```

If the output differs, update the `admin` address in `config/caddy/Caddyfile` before deployment.

## 4. Manually back up and copy the Caddy configuration

Run these commands from the repository root. Preserve the `snippets` directory structure because the deployed Caddyfile imports it.

```bash
timestamp=$(date +%Y%m%d%H%M%S)
backup="/etc/caddy/backups/caddy-$timestamp.tar.gz"

sudo mkdir -p /etc/caddy/backups /etc/caddy/snippets/domains /etc/caddy/snippets/headers
sudo tar -czf "$backup" -C /etc/caddy Caddyfile snippets 2>/dev/null || \
    sudo tar -czf "$backup" -C /etc/caddy Caddyfile
sudo cp config/caddy/Caddyfile /etc/caddy/Caddyfile
sudo cp config/caddy/snippets/wp-common.caddy /etc/caddy/snippets/wp-common.caddy
sudo cp config/caddy/snippets/disallowed-*.caddy /etc/caddy/snippets/
sudo cp config/caddy/snippets/headers/*.caddy /etc/caddy/snippets/headers/
sudo cp config/caddy/snippets/domains/*.caddy /etc/caddy/snippets/domains/
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl restart caddy
```

If validation or reload fails, use the standalone rollback script:

```bash
sudo ./scripts/rollback-caddy.sh "$backup"
```

For an automated deployment, use the repository script instead:

```bash
sudo ./scripts/deploy-caddy.sh
```

The script validates a staged copy before touching `/etc/caddy`, creates a timestamped backup under `/etc/caddy/backups/`, copies the complete package, and reloads Caddy. Rollback is intentionally separate:

```bash
sudo ./scripts/rollback-caddy.sh
```

## 5. Check routing and certificates

```bash
curl -fsSI https://geo.akilimo.org/
curl -fsSI https://stats.akilimo.org/
curl -fsSI https://sonar.munywele.co.ke/
curl -fsSI https://kvuno.agwise.org/
```

Check the response status, certificate, and expected upstream response for each domain. Test both new and existing domains before considering deployment complete.

## 6. Verify cache behavior

Issue each request twice and inspect the cache headers:

```bash
curl -sSI https://geo.akilimo.org/ | grep -Ei 'cache-status|age|cache-control'
curl -sSI https://geo.akilimo.org/ | grep -Ei 'cache-status|age|cache-control'
curl -sSI https://stats.akilimo.org/ | grep -Ei 'cache-status|age|cache-control'
curl -sSI https://stats.akilimo.org/ | grep -Ei 'cache-status|age|cache-control'
```

Expect a miss followed by a hit for cacheable `GET` responses. `Cache-Status` should identify the cache handler and show a TTL. `Age` should increase on a hit. Do not expect caching for rejected paths, non-GET methods, dynamic API responses, or authenticated dashboards.

## 7. Roll back if necessary

Use the standalone rollback script from the repository root:

```bash
sudo ./scripts/rollback-caddy.sh
```

To select a specific backup:

```bash
sudo ./scripts/rollback-caddy.sh /etc/caddy/backups/caddy-YYYYMMDDHHMMSS.tar.gz
```

The script backs up the current live configuration, extracts the selected backup, validates `/etc/caddy/Caddyfile`, and reloads Caddy.
