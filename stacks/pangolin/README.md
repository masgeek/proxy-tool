# Pangolin

Pangolin runs with Gerbil and Traefik for tunneling on a dedicated public IP. Its `80/443` listeners do not conflict with host Caddy because they bind to `PANGOLIN_PUBLIC_IP`.

## Setup

1. Set `PANGOLIN_PUBLIC_IP=20.102.57.207` in `.env` or Dokploy.
2. Generate a server secret:

   ```bash
   openssl rand -hex 32
   ```

3. Set `SERVER_SECRET` in Dokploy’s stack environment. Pangolin reads this environment variable and overrides the tracked placeholder in `config/config.yml`.
4. Set `STACK_REVISION` when deploying.
5. Start the stack:

   ```bash
   docker compose --env-file .env config --quiet
   docker compose up -d
   ```

Pangolin/Traefik binds these host ports on the dedicated private IP:

- `8080/tcp` and `8443/tcp`
- `51820/udp` and `21820/udp`

Configure Azure load balancing/port mapping from public `20.102.57.207:80` to `10.2.0.5:8080` and public `20.102.57.207:443` to `10.2.0.5:8443`. This leaves host Caddy’s existing `80/443` listeners untouched.

Point `pangolin.munywele.co.ke` DNS at the dedicated IP. Complete first-time setup at:

```text
https://pangolin.munywele.co.ke/auth/initial-setup
```

Use the setup token printed in the Pangolin logs:

```bash
docker compose logs pangolin
```
