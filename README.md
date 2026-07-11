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

- `packages/synkfeed_core`: Dart core package with models, RSS parsing, a local repository abstraction, and unit tests.
- `apps/reader`: Flutter shell built on top of the core package.
- `docs/decisions`: architecture notes and ADRs.

## Local Checks

- The core package can be tested with the Dart SDK: `cd packages/synkfeed_core && dart test`.
- The Flutter app shell is scaffolded for later validation once the Flutter SDK is installed.

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
