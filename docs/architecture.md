# Architecture

SynkFeed is split into a local-first Flutter reader and an optional synchronization
service.

## Reader

The UI reads from `LocalFeedRepository`. The production adapter stores feeds,
subscriptions, articles, article states, retention settings, client sequences,
and pending operations in SQLite. Read/favorite changes and their sync operation
are committed in one transaction. HTTP feed imports populate SQLite before the
UI reloads, so previously downloaded content never depends on API availability.

## Client synchronization

`SyncApiClient` speaks the server HTTP API, `SessionStore` persists the rotated
token pair per device, and `SyncEngine` replays pending local operations before
downloading the change log from the stored cursor. Operations recorded while
signed out are rebound to the authenticated device inside one SQLite transaction
before their first push. Applied changes and the advanced cursor are committed
atomically, so an interrupted pull resumes without loss or duplication.

## Server

The Fastify API authenticates short-lived access tokens and rotates hashed refresh
tokens. PostgreSQL owns synchronized accounts, devices, subscriptions, articles,
accepted operation IDs, and the ordered change log. A separate worker fetches
RSS/Atom sources with conditional requests, response limits, redirect validation,
timeouts, and DNS-level private-address rejection.

## Deployment

Docker Compose starts PostgreSQL, a one-shot migration container, the API, and the
collector. Internet-facing deployments must terminate HTTPS at a reverse proxy.
