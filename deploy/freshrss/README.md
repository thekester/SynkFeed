# FreshRSS deployment

FreshRSS is the recommended multi-user backend for the SynkFeed reader: the app
speaks its Google Reader-compatible API (`api/greader.php`) and downloads
article content exactly as FreshRSS stores it.

## Start

```bash
mkdir -p data extensions
docker compose up -d
```

Then open `http://<server>:8081` and run the first-install wizard (SQLite is
fine for a family instance). All state lives in the mounted `data/` directory;
backing it up is enough to restore the instance.

## Enable the API for each user

1. Administration > Authentication: check "Allow API access".
2. For every user: Settings > Profile > API management: set an **API
   password** (this is the password the SynkFeed app asks for, not the login
   password).
3. In the SynkFeed reader: sync button > FreshRSS, server URL
   `http://<server>:8081`, username, API password.

## Full article content (not just the preview)

Many feeds only publish an excerpt. FreshRSS can fetch the complete article
from the original website:

- Per feed: Feed settings > Advanced > "Article CSS selector on original
  website" - e.g. `article`, `div.entry-content`, or the site-specific
  selector. FreshRSS then downloads and stores the full text, which the
  SynkFeed app (and every other client) receives for offline reading.
- The refresh cron inside the container (`CRON_MIN`) keeps articles current.

## HTTPS

The compose file publishes plain HTTP on port 8081. Before inviting users over
the internet, put a reverse proxy with a domain and TLS in front (Caddy or
Traefik) and rebind the port to `127.0.0.1:8081:80`.
