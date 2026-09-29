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

Pangolin/Traefik binds these ports on the dedicated IP:

- `80/tcp` and `443/tcp`
- `51820/udp` and `21820/udp`

Point `pangolin.munywele.co.ke` DNS at the dedicated IP. Complete first-time setup at:

```text
https://pangolin.munywele.co.ke/auth/initial-setup
```

Use the setup token printed in the Pangolin logs:

```bash
docker compose logs pangolin
```
