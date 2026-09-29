# Pangolin

Pangolin runs in dashboard-only mode behind the host Caddy reverse proxy. Gerbil and Pangolin Traefik are not started, so Pangolin does not claim host ports `80/443`.

## Setup

1. Generate a server secret:

   ```bash
   openssl rand -hex 32
   ```

2. Set `SERVER_SECRET` in Dokploy’s stack environment. Pangolin reads this environment variable and overrides the tracked placeholder in `config/config.yml`, so the secret never needs to be committed.
3. Copy `.env.example` to `.env` and set `STACK_REVISION` when deploying.
4. Start the stack:

   ```bash
   docker compose --env-file .env config --quiet
   docker compose up -d
   ```

Pangolin publishes loopback-only upstreams:

- API: `127.0.0.1:9320`
- Dashboard UI: `127.0.0.1:9322`

The host Caddy route is `pangolin.munywele.co.ke`. Complete first-time setup at:

```text
https://pangolin.munywele.co.ke/auth/initial-setup
```

Use the setup token printed in the Pangolin logs:

```bash
docker compose logs pangolin
```

This mode does not provide Pangolin tunneling or dynamic public resources; those require Pangolin Traefik/Gerbil and dedicated public `80/443` ownership.
