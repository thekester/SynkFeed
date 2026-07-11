# SynkFeed

Open-source, offline-first RSS reader for Android, Windows, and Linux, with seamless multi-device synchronization.

## Repository Language

- All code, documentation, issues, pull requests, and commit messages should be written in English.
- This repository does not use French for project-facing content.

## AI-Assisted Development

- AI can be used to draft, refactor, review, and test code.
- Human review is still required before merging or releasing changes.
- Any AI-generated code must be validated with tests and checked for correctness, security, and maintainability.

## Current Layout

- `packages/synkfeed_core`: Dart core package with models, RSS/Atom downloading and parsing, SQLite persistence, a local repository abstraction, and unit tests.
- `apps/reader`: Flutter reader shell backed by a persistent offline library.
- `server`: Fastify API, PostgreSQL migrations, authentication, synchronization, and RSS collector.
- `docs/decisions`: architecture notes and ADRs.

## Local Checks

- The core package can be tested with the Dart SDK: `cd packages/synkfeed_core && dart test`.
- The Flutter app can be checked with `cd apps/reader && flutter analyze && flutter test`.
- The server can be checked with `cd server && npm ci && npm run typecheck && npm test`.

## Current Reader Flow

- Add an HTTP(S) RSS or Atom URL from the app.
- SynkFeed downloads and parses the feed with response-size and timeout limits.
- Feeds, articles, read/favorite states, and pending sync operations are stored in
  the local SQLite database.
- Refreshes use `ETag` and `Last-Modified` when publishers provide them.
- Article state changes update locally and enter the persistent operation queue in
  one SQLite transaction.

## Self-hosting

Copy `.env.example` to `.env`, replace the example secrets, then run
`docker compose up --build -d`. See [the self-hosting guide](docs/self-hosting.md)
for HTTPS and backup guidance.

## GitHub Actions

- `ci.yml` runs Dart and Flutter checks on pushes and pull requests.
- `build-packages.yml` produces release artifacts for Android APK, Windows ZIP, and Linux tarball on manual dispatch or tags.
- The Android artifact is a signed release APK. Configure these GitHub secrets before running release builds:
  - `ANDROID_KEYSTORE_BASE64`
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`
- Create the keystore with `keytool`, base64-encode the `.jks` file, and store the passwords and alias as GitHub secrets.
- Windows and Linux builds are release builds, but they are not code-signed yet.

## Specification

Detailed specification: [OPEN_RSS_READER_SPEC.md](./OPEN_RSS_READER_SPEC.md)
