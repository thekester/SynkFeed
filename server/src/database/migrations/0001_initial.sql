CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL,
  password_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  deleted_at timestamptz,
  CONSTRAINT users_normalized_email_unique UNIQUE (email)
);

CREATE TABLE devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  platform text NOT NULL,
  last_synced_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX devices_user_id ON devices(user_id);

CREATE TABLE refresh_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  token_hash text NOT NULL UNIQUE,
  expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  replaced_by uuid REFERENCES refresh_tokens(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_active ON refresh_tokens(token_hash) WHERE revoked_at IS NULL;

CREATE TABLE feeds (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  canonical_url text NOT NULL UNIQUE,
  feed_url text NOT NULL UNIQUE,
  site_url text,
  title text NOT NULL,
  description text,
  etag text,
  last_modified timestamptz,
  last_fetched_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE articles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  feed_id uuid NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  external_id text NOT NULL,
  canonical_url text NOT NULL,
  title text NOT NULL,
  author text,
  summary text,
  content_html text,
  content_text text,
  published_at timestamptz,
  updated_at timestamptz,
  content_hash text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (feed_id, external_id)
);
CREATE INDEX articles_feed_published ON articles(feed_id, published_at DESC);

CREATE TABLE subscriptions (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  feed_id uuid NOT NULL REFERENCES feeds(id) ON DELETE CASCADE,
  custom_title text,
  is_muted boolean NOT NULL DEFAULT false,
  deleted_at timestamptz,
  logical_version bigint NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, feed_id)
);

CREATE TABLE article_states (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  article_id uuid NOT NULL REFERENCES articles(id) ON DELETE CASCADE,
  is_read boolean NOT NULL DEFAULT false,
  read_at timestamptz,
  is_starred boolean NOT NULL DEFAULT false,
  starred_at timestamptz,
  is_archived boolean NOT NULL DEFAULT false,
  logical_version bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, article_id)
);
CREATE INDEX article_states_user_filters ON article_states(user_id, is_read, is_starred);

CREATE TABLE accepted_operations (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  operation_id text NOT NULL,
  device_id uuid NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  client_sequence bigint NOT NULL,
  accepted_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, operation_id),
  UNIQUE (device_id, client_sequence)
);

CREATE TABLE change_log (
  cursor bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entity_type text NOT NULL,
  entity_id text NOT NULL,
  operation_type text NOT NULL,
  data jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX change_log_user_cursor ON change_log(user_id, cursor);
