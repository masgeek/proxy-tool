# Stats API

The Stats API runs as an independent stack on `127.0.0.1:9511`. It queries GeoServer through the public `https://geo.akilimo.org/geoserver` URL and is exposed publicly through the `stats.akilimo.org` Caddy route.

## Setup

```bash
cp .env.example .env
docker compose --env-file .env config --quiet
docker compose up -d
```

Set `GEOSERVER_BASE` if the GeoServer URL changes. Deploy the GeoServer stack separately; the two stacks share the named `internal` and `dokploy-network` networks.
