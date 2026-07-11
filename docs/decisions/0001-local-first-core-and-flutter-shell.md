# ADR 0001: Local-First Core and Flutter Shell

Status: accepted

## Context

SynkFeed must stay usable offline, queue actions locally, and synchronize later without blocking the interface.

## Decision

- Keep the core domain logic in a pure Dart package (`packages/synkfeed_core`).
- Build the user interface as a Flutter app shell in `apps/reader`.
- Model feeds, articles, article state, and sync operations in the core package first.
- Use a local repository abstraction so the storage layer can move to SQLite/Drift later without changing UI code.
- Seed the first app build with demo RSS and Atom content so the offline-first flow is visible immediately.

## Consequences

- Core logic can be tested with the Dart SDK even when the Flutter SDK is not available.
- The Flutter app can start from a small, deterministic surface instead of a server-first architecture.
- Storage and synchronization can be replaced progressively with SQLite, Drift, and the server API.
- The repository remains aligned with the specification's offline-first requirement.
