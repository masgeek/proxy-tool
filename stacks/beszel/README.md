# Beszel

This stack runs the Beszel hub and host agent. The hub UI is bound to `127.0.0.1:9625`; the agent is internal and uses port `45876`.

## Setup

1. Copy the environment file:

   ```bash
   cp .env.example .env
   ```

2. Start the hub first:

   ```bash
   docker compose up -d hub
   ```

3. Open the hub through an SSH tunnel:

   ```bash
   ssh -L 9625:127.0.0.1:9625 user@your-server
   ```

   Open `http://127.0.0.1:9625` locally.

4. In the hub, open **Settings → Tokens** and create a universal token.
5. Set `BESZEL_UNIVERSAL_TOKEN` in `.env`. The agent will auto-register without a per-system key.
6. Start the agent:

   ```bash
   docker compose up -d agent
   ```

## Access

The optional public route is `beszel.munywele.co.ke`; merge `Caddyfile` into the host Caddyfile. The agent Docker socket mount is read-only, but the agent still requires permission to read it.
