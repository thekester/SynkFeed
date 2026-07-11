# ADR 0002: SQLite Persistence Adapter

Status: accepted

## Context

The initial reader shell used an in-memory repository. Feeds, downloaded articles,
article states, pending synchronization operations, and client sequences therefore
disappeared whenever the application restarted.

The specification requires SQLite-backed local storage on Android, Windows, and
Linux, atomic state-and-operation writes, progressive migrations, and a UI that
never depends on a network response to display downloaded content.

## Decision

- Keep `LocalFeedRepository` as the boundary between the UI and storage.
- Add a SQLite implementation using the cross-platform `sqlite3` package.
- Version the schema through SQLite's `user_version` pragma and run migrations
  when the repository opens.
- Write an article-state change and its pending synchronization operation in the
  same transaction.
- Persist a monotonically increasing client sequence per device.
- Keep the in-memory implementation for fast unit and widget tests.

Drift remains a possible future adapter if reactive generated queries become
valuable. Keeping the repository boundary prevents that change from affecting
feature and UI code.

## Consequences

- Downloaded text and local actions survive application restarts.
- Repository tests can exercise a real temporary SQLite file.
- Schema changes must include a versioned migration and a migration test.
- Reactive updates are currently driven explicitly by the controller after local
  writes rather than by database watch queries.
