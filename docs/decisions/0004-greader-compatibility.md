# ADR 0004: Google Reader API Compatibility (FreshRSS)

Status: accepted

## Context

The household already wants a shared, self-hosted feed service usable by
several people and by existing mobile clients. FreshRSS provides accounts,
feed refresh, full-content retrieval, and a widely implemented Google
Reader-compatible API. The native SynkFeed server does not yet map local
content-derived article IDs to server UUIDs, which limits state sync.

## Decision

- Add a `GReaderApiClient` (ClientLogin, subscription/list, stream contents,
  stream item IDs, token, edit-tag) and a `GReaderSyncEngine` to the core
  package.
- Treat the Google Reader server as the source of subscriptions and articles;
  prefix synchronized entities with `greader-` so local operations map back to
  server item IDs.
- Replay local read/star operations through `edit-tag`; reconcile state from
  the server's unread and starred ID sets, writing states directly so
  reconciliation never re-queues pending operations.
- Reject pending operations on entities unknown to the server with
  `not_linked`.
- Keep the native SynkFeed backend; the account dialog selects the backend and
  the stored session records it.

## Consequences

- Full offline article content depends on the FreshRSS feed configuration
  (CSS selector retrieval), not on the reader.
- Read/favorite state is shared with any other FreshRSS client used by the
  same account.
- The GoogleLogin token does not rotate; a 401 clears the session and requires
  a new sign-in.
