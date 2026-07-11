# Synchronization Protocol

All synchronization routes require a bearer access token tied to an active device.

## Push

`POST /v1/sync/push` accepts at most 500 operations. Each operation contains a
globally stable operation ID, the authenticated device ID, a monotonically
increasing client sequence, an entity ID, an operation type, and a payload.

The server checks `(user_id, operation_id)` before applying an operation. Replays
are returned as accepted without applying their effect again. A distinct operation
that reuses a device sequence is rejected with `client_sequence_conflict`.
Accepted state changes and their journal entry share one PostgreSQL transaction.

## Pull

`GET /v1/sync/pull?cursor=0&limit=200` returns changes in strictly increasing
cursor order. `limit` is capped at 500. The response contains `nextCursor` and
`hasMore`; clients continue until `hasMore` is false.

Clients must store applied data and `nextCursor` atomically. They acknowledge local
operations only after the push response lists them as accepted. Interrupted pushes
and pulls can therefore be replayed safely.

## Conflict rule

For MVP article read and favorite state, the last operation accepted by PostgreSQL
wins. Client timestamps are diagnostic only; server journal order is authoritative.

## Client transport

The Dart `SyncEngine` implements the client side of this protocol:

- Operations recorded before sign-in carry a placeholder device identity. Before
  the first push they are rebound to the authenticated device with fresh client
  sequences and rewritten operation IDs, in one local transaction.
- Pushes are batched at 500 operations. Accepted IDs are acknowledged locally;
  per-operation rejections are stored with their error code and leave the pending
  queue. If the server refuses a whole batch with HTTP 400, every operation in
  the batch is marked rejected with that code.
- On HTTP 401 the engine refreshes the token pair once, persists the rotated
  session, and retries the request. A rejected refresh token or a
  `device_revoked` response clears the stored session and requires a new sign-in.
- Pulled changes and the advanced cursor are applied in a single local
  transaction. Changes referencing articles unknown locally are skipped while
  the cursor still advances.

Known MVP limitation: local article IDs are content-derived while server article
IDs are UUIDs assigned by the collector. Until subscription and article identity
mapping lands, article-state pushes for locally imported articles are rejected
with `invalid_request` or `article_not_found`, and pulled states apply only to
articles whose IDs are known locally.
