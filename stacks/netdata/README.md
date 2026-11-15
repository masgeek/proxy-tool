# Netdata

Netdata is the standalone host and Docker metrics stack. It does not collect or query application logs; those remain in `stacks/monitoring/` through Alloy and Loki.

## Setup

1. Copy the environment file:

   ```bash
   cp .env.example .env
   ```

2. Validate and start:

   ```bash
   docker compose --env-file .env config --quiet
   docker compose up -d
   ```

3. Verify locally:

   ```bash
   curl http://127.0.0.1:19999
   ```

Netdata requires host PID/network access, host `/proc` and `/sys`, the Docker socket, `SYS_ADMIN`, and `SYS_PTRACE`. Its web listener is restricted to `127.0.0.1` by `netdata.conf`; expose it publicly only through `Caddyfile` at `monitor.munywele.co.ke`.
