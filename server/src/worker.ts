import { loadConfig } from "./config.js";
import { createDatabase, type Database } from "./database/pool.js";
import { parseFeed } from "./workers/feed_parser.js";
import { safeFetch } from "./workers/safe_fetch.js";

const config = loadConfig();
const database = createDatabase(config.DATABASE_URL);
let stopping = false;

for (const signal of ["SIGINT", "SIGTERM"] as const) {
  process.on(signal, () => {
    stopping = true;
  });
}

while (!stopping) {
  await collectDueFeeds(database).catch((error: unknown) => {
    process.stderr.write(`collector cycle failed: ${safeErrorCode(error)}\n`);
  });
  if (!stopping) await delay(config.RSS_FETCH_INTERVAL_SECONDS * 1_000);
}
await database.close();

async function collectDueFeeds(database: Database): Promise<void> {
  const feeds = await database.query<{
    id: string;
    feed_url: string;
    etag: string | null;
    last_modified: Date | null;
  }>(
    `SELECT id, feed_url, etag, last_modified FROM feeds
     WHERE last_fetched_at IS NULL
        OR last_fetched_at < now() - ($1 * interval '1 second')
     ORDER BY last_fetched_at NULLS FIRST LIMIT 50`,
    [config.RSS_FETCH_INTERVAL_SECONDS],
  );
  for (const feed of feeds.rows) await collectFeed(database, feed);
}

async function collectFeed(
  database: Database,
  feed: { id: string; feed_url: string; etag: string | null; last_modified: Date | null },
): Promise<void> {
  const started = Date.now();
  try {
    const headers: Record<string, string> = {
      accept: "application/atom+xml, application/rss+xml, application/xml, text/xml;q=0.9",
      "user-agent": "SynkFeed-Collector/0.1",
    };
    if (feed.etag !== null) headers["if-none-match"] = feed.etag;
    if (feed.last_modified !== null) headers["if-modified-since"] = feed.last_modified.toUTCString();
    const { response, body } = await safeFetch(feed.feed_url, {
      headers,
      maximumBytes: config.RSS_MAX_RESPONSE_SIZE,
    });
    if (response.status === 304) {
      await recordFetch(database, feed.id, "not_modified", 304, null, started);
      return;
    }
    if (!response.ok) throw new Error(`http_${response.status}`);
    const parsed = parseFeed(body, feed.feed_url);
    await database.transaction(async (client) => {
      await client.query(
        `UPDATE feeds SET title = $2, site_url = $3, description = $4,
           etag = $5, last_modified = $6, last_fetched_at = now(), updated_at = now()
         WHERE id = $1`,
        [
          feed.id,
          parsed.title,
          parsed.siteUrl,
          parsed.description,
          response.headers.get("etag"),
          response.headers.get("last-modified"),
        ],
      );
      for (const article of parsed.articles) {
        await client.query(
          `INSERT INTO articles(
             feed_id, external_id, canonical_url, title, author, summary,
             content_html, published_at, updated_at
           ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
           ON CONFLICT(feed_id, external_id) DO UPDATE SET
             canonical_url = excluded.canonical_url, title = excluded.title,
             author = excluded.author, summary = excluded.summary,
             content_html = excluded.content_html, published_at = excluded.published_at,
             updated_at = excluded.updated_at`,
          [
            feed.id,
            article.externalId,
            article.canonicalUrl,
            article.title,
            article.author,
            article.summary,
            article.contentHtml,
            article.publishedAt,
            article.updatedAt,
          ],
        );
      }
      await client.query(
        `INSERT INTO feed_fetch_history(feed_id, status, http_status, duration_ms)
         VALUES ($1, 'success', $2, $3)`,
        [feed.id, response.status, Date.now() - started],
      );
    });
  } catch (error) {
    await recordFetch(database, feed.id, "error", null, safeErrorCode(error), started);
  }
}

async function recordFetch(
  database: Database,
  feedId: string,
  status: string,
  httpStatus: number | null,
  errorCode: string | null,
  started: number,
): Promise<void> {
  await database.transaction(async (client) => {
    await client.query("UPDATE feeds SET last_fetched_at = now() WHERE id = $1", [feedId]);
    await client.query(
      `INSERT INTO feed_fetch_history(feed_id, status, http_status, error_code, duration_ms)
       VALUES ($1, $2, $3, $4, $5)`,
      [feedId, status, httpStatus, errorCode, Date.now() - started],
    );
  });
}

function safeErrorCode(error: unknown): string {
  const message = error instanceof Error ? error.message : "unknown_error";
  return message.replace(/[^a-zA-Z0-9_-]/g, "_").slice(0, 100);
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
