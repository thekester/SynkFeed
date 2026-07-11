# Self-hosting SynkFeed

Two backends can serve the reader:

- **FreshRSS** (recommended for multi-user family setups): the reader speaks
  its Google Reader-compatible API, including full article content and shared
  read/favorite state across every FreshRSS client. See
  [`deploy/freshrss/`](../deploy/freshrss/README.md).
- **The native SynkFeed server** (this document): the custom Fastify/PostgreSQL
  service with per-device operation-log synchronization.

## Requirements

- Docker Engine 24 or newer
- Docker Compose v2
- A reverse proxy providing HTTPS for any non-local deployment

## Start the services

1. Copy `.env.example` to `.env`.
2. Replace `POSTGRES_PASSWORD` and `JWT_SECRET` with independent random values.
3. Run `docker compose up --build -d`.
4. Verify readiness with `curl http://localhost:3000/health/ready`.

The Compose project starts PostgreSQL, runs pending migrations once, then starts
the API and RSS collector. PostgreSQL data is stored in the `postgres-data`
volume.

## HTTPS

The API intentionally serves plain HTTP inside the container network. Put it
behind Caddy, Traefik, nginx, or another reverse proxy and require HTTPS outside
local development. Only configure `CORS_ALLOWED_ORIGINS` if a browser client
needs access.

## Backup and restore

Create a logical backup:

```sh
docker compose exec -T postgres pg_dump -U synkfeed -Fc synkfeed > synkfeed.dump
```

Restore into an empty database:

```sh
docker compose exec -T postgres pg_restore -U synkfeed -d synkfeed --clean --if-exists < synkfeed.dump
```

Store backups separately from the Docker host and test restoration regularly.
