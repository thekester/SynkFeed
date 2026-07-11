# ADR 0003: Fastify, PostgreSQL, and an Operation Log

Status: accepted

## Context

Multiple offline devices must replay actions without duplicates and resume change
downloads after interruption. Device clocks cannot provide reliable ordering.

## Decision

- Use Fastify with validated TypeScript route inputs.
- Use PostgreSQL transactions for synchronized state and its change-log entry.
- Deduplicate pushes by user and operation ID.
- Reject reuse of a device client sequence by another operation.
- Assign each outbound change a PostgreSQL identity cursor.
- Store only SHA-256 hashes of random refresh tokens and rotate on every refresh.
- Fetch feeds in a separate worker with network and response limits.

## Consequences

- Push and pull can be retried safely.
- Conflict ordering follows server acceptance rather than client wall clocks.
- Old change-log rows and subscription tombstones need a documented retention and
  full-resynchronization policy before production-scale cleanup is enabled.
