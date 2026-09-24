# Testing the Production Caddyfile

Run these checks on the production host before reloading Caddy. Do not overwrite the live configuration until both validation commands pass.

## 1. Verify the compiled modules

```bash
caddy list-modules | grep -E 'http.handlers.cache|cache'
```

The output must include the cache handler module. If it does not, do not deploy the cache configuration.

## 2. Validate the repository file

```bash
caddy adapt --config ./Caddyfile --adapter caddyfile >/tmp/caddy-adapted.json
caddy validate --config ./Caddyfile --adapter caddyfile
```

Both commands must exit successfully. Keep `/tmp/caddy-adapted.json` when troubleshooting because it shows the handlers Caddy will actually run.

## 3. Verify the Docker bridge address

The aggregate Caddyfile binds the admin API to `172.17.0.1:2019`. Confirm that this is the host-side Docker bridge address:

```bash
docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}'
```

If the output differs, update the `admin` address in `Caddyfile` before deployment.

## 4. Back up and install the live configuration

```bash
sudo cp /etc/caddy/Caddyfile "/etc/caddy/Caddyfile.bak.$(date +%Y%m%d%H%M%S)"
sudo install -m 0644 ./Caddyfile /etc/caddy/Caddyfile
sudo caddy validate --config /etc/caddy/Caddyfile
sudo caddy reload --config /etc/caddy/Caddyfile
```

If validation or reload fails, restore the backup and do not continue testing the new configuration.

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
