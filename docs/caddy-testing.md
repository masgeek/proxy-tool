# Testing the Production Caddyfile

Run these checks on the production host before reloading Caddy. Do not overwrite the live configuration until both validation commands pass.

## 1. Verify the compiled modules

```bash
caddy list-modules | grep -E 'http.handlers.cache|cache'
```

The output must include the cache handler module. If it does not, do not deploy the cache configuration.

## 2. Validate the repository file

```bash
caddy adapt --config config/caddy/Caddyfile --adapter caddyfile >/tmp/caddy-adapted.json
caddy validate --config config/caddy/Caddyfile --adapter caddyfile
```

Both commands must exit successfully. Keep `/tmp/caddy-adapted.json` when troubleshooting because it shows the handlers Caddy will actually run.

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

sudo mkdir -p /etc/caddy/backups /etc/caddy/snippets/domains
sudo tar -czf "$backup" -C /etc/caddy Caddyfile snippets 2>/dev/null || \
    sudo tar -czf "$backup" -C /etc/caddy Caddyfile
sudo cp config/caddy/Caddyfile /etc/caddy/Caddyfile
sudo cp config/caddy/snippets/common.caddy /etc/caddy/snippets/common.caddy
sudo cp config/caddy/snippets/domains/*.caddy /etc/caddy/snippets/domains/
sudo caddy validate --config /etc/caddy/Caddyfile
sudo caddy reload --config /etc/caddy/Caddyfile
```

If validation or reload fails, use the standalone rollback script:

```bash
sudo ./scripts/rollback-caddy.sh "$backup"
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

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
sudo caddy reload --config /etc/caddy/Caddyfile
```

To roll back, copy the most recent `/etc/caddy/Caddyfile.bak.*` file over `/etc/caddy/Caddyfile`, validate it, and reload Caddy.
