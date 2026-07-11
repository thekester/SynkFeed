CREATE TABLE feed_fetch_history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  feed_id uuid NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  status text NOT NULL,
  http_status integer,
  error_code text,
  duration_ms integer NOT NULL,
  fetched_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX feed_fetch_history_feed_time ON feed_fetch_history(feed_id, fetched_at DESC);
