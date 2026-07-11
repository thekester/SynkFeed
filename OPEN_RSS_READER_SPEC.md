# Specification - open-source, cross-platform, offline-first RSS reader

> Functional and technical specification intended to guide development with Codex.

## 1. Project Vision

Build a modern, open-source, cross-platform RSS reader that can work without Internet access and automatically synchronize read state across multiple devices when the network becomes available again.

The project should provide:

- an Android app distributable as an APK and, optionally, as an AAB on Google Play;
- a desktop app for Windows and Linux;
- a mostly shared client codebase thanks to Flutter;
- a local SQLite database on each device;
- a self-hostable synchronization server;
- a Node.js API backed by PostgreSQL;
- an open-source release on GitHub under the MIT license.

The core principle is: **the application must remain usable when the server or the Internet is unavailable**. The server synchronizes devices, but the local database keeps the app working.

---

## 2. Main Objectives

### 2.1 Functional Objectives

The user must be able to:

1. create an account and connect multiple devices;
2. add, edit, and remove RSS or Atom subscriptions;
3. import and export subscriptions in OPML format;
4. read articles available locally without a connection;
5. mark an article as read or unread;
6. add or remove an article from favorites;
7. synchronize those states across Android, Windows, and Linux;
8. keep using the app offline;
9. send pending actions when the network returns;
10. choose how much content is kept on each device;
11. use the software without creating an account, in local-only mode;
12. self-host the synchronization server.

### 2.2 Technical Objectives

- Maximize code sharing across Android, Windows, and Linux.
- Design a robust offline-first architecture.
- Never block the UI while waiting for the server.
- Synchronize only the necessary changes.
- Handle modification conflicts deterministically.
- Avoid duplicate articles.
- Protect accounts and synchronized data.
- Allow progressive migrations of both the local and server databases.
- Provide approachable installation and contribution workflows.

### 2.3 Out of Scope for the Initial MVP

The following features are not required for the MVP:

- iOS or macOS versions;
- a full web reading portal;
- algorithmic recommendations;
- social networking or public comments;
- automatic video downloads;
- universal full-page content extraction;
- direct peer-to-peer synchronization between devices;
- end-to-end encryption of the entire synchronized database.

---

## 3. Target Platforms

| Platform | Technology | Expected Deliverable |
|---|---|---|
| Android | Flutter | APK, then optionally AAB |
| Windows | Flutter Desktop | Packaged app, MSIX or EXE installer |
| Linux | Flutter Desktop | Archive, DEB package, AppImage, or Flatpak |
| Server | Node.js + PostgreSQL | Docker images and Docker Compose |
| Admin web | Optional | Account and device management interface |

The Android, Windows, and Linux applications should share:

- business models;
- SQLite access;
- the synchronization engine;
- RSS logic;
- authentication;
- cache management;
- most UI components.

Platform-specific adaptations remain allowed for:

- navigation;
- panel size and layout;
- notifications;
- background tasks;
- secure token storage;
- system tray integration;
- keyboard shortcuts;
- installers and updates.

---

## 4. General Architecture

```text
Android application  ---> HTTPS ---> Synchronization API ---> PostgreSQL
Windows application  ---> HTTPS ---> Synchronization API ---> PostgreSQL
Linux application    ---> HTTPS ---> Synchronization API ---> PostgreSQL

On each device: Flutter + SQLite + file cache + operation queue
```

### 4.1 Flutter Client

The client is a complete local application. The interface reads data from SQLite, not directly from the API.

Responsibilities:

- display feeds and articles;
- write user actions to SQLite immediately;
- maintain a queue of unsynchronized operations;
- trigger synchronization;
- download selected images for offline use;
- clean the cache according to user preferences;
- keep a synchronization cursor per account and device.

### 4.2 Node.js API

Responsibilities:

- authenticate users and devices;
- store subscriptions;
- expose new articles;
- receive operations performed by clients;
- resolve or record conflicts;
- produce an ordered stream of changes;
- manage sessions and device revocations;
- provide health and monitoring endpoints.

A TypeScript implementation with Fastify is recommended. Express remains acceptable if simplicity is preferred.

### 4.3 PostgreSQL

PostgreSQL is the central source of truth for synchronized data. It should not be required to read articles that are already present on a device.

### 4.4 RSS Collector

A server-side worker periodically fetches feeds in order to:

- avoid having each device query the same sources;
- standardize deduplication;
- discover new articles even when no client is open;
- respect fetch intervals and conditional HTTP responses.

The collector must support:

- RSS 2.0;
- Atom;
- HTTP redirects;
- `ETag` and `If-None-Match`;
- `Last-Modified` and `If-Modified-Since`;
- temporary errors and retries with backoff;
- a response size limit;
- protection against requests to internal addresses.

---

## 5. Offline-First Principle

### 5.1 Immediate UI Source

The UI must always read from SQLite:

```text
User action
    ->
Immediate write to SQLite
    ->
Add an operation to the local queue
    ->
Immediate UI update
    ->
Sync now or later
```

A network outage must not cause:

- already downloaded articles to disappear;
- the inability to mark an article as read;
- a permanent loading screen;
- loss of performed actions;
- silent cancellation of changes.

### 5.2 Local Mode Without an Account

The app should work without an account:

- subscriptions and articles remain on the device;
- no remote synchronization is performed;
- the user can create an account later;
- there must be a way to associate or merge local data with the account.

### 5.3 Connectivity States

The engine must distinguish between:

- **offline**: no immediate attempt;
- **network available, server unreachable**: deferred retry;
- **authentication expired**: refresh token renewal;
- **account revoked**: suspend synchronization and notify the user;
- **active synchronization**: send then receive changes;
- **synced**: no pending local operations;
- **partial error**: keep unaccepted operations.

---

## 6. Local Storage

### 6.1 Technologies

- SQLite as the local engine.
- Drift recommended for typed access, migrations, and reactive queries.
- Separate files for images and other media.
- Native secure storage for secrets and tokens.

### 6.2 Minimal Local Tables

#### `feeds`

```text
id
canonical_url
feed_url
site_url
title
description
language
icon_url
local_icon_path
etag
last_modified
last_fetched_at
created_at
updated_at
```

#### `subscriptions`

```text
id
user_id
feed_id
folder_id
custom_title
is_muted
created_at
updated_at
deleted_at
sync_version
```

#### `articles`

```text
id
feed_id
external_id
canonical_url
title
author
summary
content_html
content_text
published_at
updated_at
downloaded_at
estimated_reading_time
content_hash
```

#### `article_states`

```text
user_id
article_id
is_read
read_at
is_starred
starred_at
is_archived
updated_at
logical_version
```

#### `media_cache`

```text
id
article_id
remote_url
local_path
mime_type
file_size
checksum
download_status
last_accessed_at
```

#### `sync_operations`

```text
operation_id
device_id
entity_type
entity_id
operation_type
payload_json
client_sequence
created_at
attempt_count
last_attempt_at
status
error_code
```

#### `sync_state`

```text
account_id
device_id
last_server_cursor
last_successful_sync_at
last_attempt_at
sync_status
```

### 6.3 Media

Images should not be stored as SQLite BLOBs by default. The app should keep:

- the file in a cache directory;
- its path in SQLite;
- its checksum;
- its size;
- its download state.

Videos and audio files are not automatically downloaded in the MVP.

### 6.4 Retention Policy

The user must be able to choose:

- 7, 30, or 90 days of retention;
- unlimited retention;
- a maximum number of articles per feed;
- a global cache limit;
- whether images are downloaded;
- images downloaded only over Wi-Fi;
- automatic retention of favorites and unread articles.

Recommended default policy:

- keep 30 days;
- keep all unread items and favorites;
- automatically download text;
- download images over Wi-Fi;
- set an initial 500 MB cap;
- prioritize removal of the least recently accessed media.

---

## 7. RSS Content and Offline Reading

Not all feeds provide the full article. There are three cases:

1. full content in the feed: full offline reading is possible;
2. summary in the feed: only the summary is guaranteed offline;
3. title and link only: offline information is limited.

The MVP must faithfully store the content provided by the feed. A later feature can fetch the page and extract a readable version.

That extraction should remain optional, because it may encounter:

- JavaScript-rendered pages;
- paywalls;
- anti-bot protections;
- restrictive terms of service;
- HTML structure changes;
- content that cannot be extracted cleanly.

HTML coming from feeds must be sanitized before display. Scripts, dangerous iframes, event handlers, and unsafe URLs must be removed or blocked.

---

## 8. Synchronization

### 8.1 General Model

Each device has:

- a stable `device_id`;
- a locally increasing `client_sequence`;
- an operation queue;
- a cursor representing the last server change received.

Synchronization has two main steps:

1. **push**: send local operations;
2. **pull**: fetch changes after the local cursor.

### 8.2 Example Operation

```json
{
  "operationId": "01J2XYZ...",
  "deviceId": "phone-theophile",
  "clientSequence": 154,
  "entityType": "article_state",
  "entityId": "article-42",
  "operationType": "mark_read",
  "payload": {
    "isRead": true
  },
  "createdAt": "2026-07-11T14:31:00Z"
}
```

### 8.3 Indicative API

```http
POST /v1/sync/push
GET  /v1/sync/pull?cursor=1842&limit=500
POST /v1/sync
```

A combined route can be added, but the protocol should remain understandable and testable.

Example response:

```json
{
  "acceptedOperations": ["01J2XYZ..."],
  "rejectedOperations": [],
  "changes": [
    {
      "cursor": 1843,
      "entityType": "article_state",
      "entityId": "article-42",
      "data": {
        "isRead": true,
        "readAt": "2026-07-11T14:31:00Z"
      }
    }
  ],
  "nextCursor": 1843,
  "hasMore": false
}
```

### 8.4 Essential Properties

- **Idempotence**: resending the same operation must not apply its effect twice.
- **Pagination**: the client must be able to fetch changes in batches.
- **Stable order**: each server change receives a strictly ordered cursor.
- **Resume support**: an interrupted sync must be able to continue.
- **Local atomicity**: data and cursor are stored in the same SQLite transaction.
- **Duplicate tolerance**: already accepted operations are recognized.
- **Observability**: errors must be identifiable without recording secrets.

### 8.5 Frequency

Synchronization can be triggered:

- at launch;
- when returning to the foreground;
- on user action, with debounce;
- manually;
- periodically when the platform allows it;
- when the network returns.

Android does not guarantee permanent background execution. The system must therefore work even if synchronization only happens at the next app open.

---

## 9. Conflict Handling

### 9.1 Initial Rules

| Data | Proposed Rule |
|---|---|
| Read/unread | Last operation accepted by the server |
| Starred/unstarred | Last operation accepted by the server |
| Subscription added | Idempotent add |
| Subscription deleted | Temporary tombstone to propagate the removal |
| Folder/label | Merge additions, explicit removal |
| Device-specific preferences | Do not sync by default |
| Account preferences | Latest server version |

### 9.2 Clocks

The phone or PC clock should not be the sole authority, because it may be wrong. Final ordering should rely on:

- the operation identifier;
- the local sequence;
- the order in which the server accepted the operation;
- a logical version assigned by the server.

The client timestamp remains useful for display and diagnostics, but not as the only arbiter.

### 9.3 Deletions

A deletion should be represented temporarily by a tombstone so that a device that stayed offline does not recreate the deleted item. A tombstone retention policy must be defined, for example 90 days, with full resynchronization for a device that is too old.

---

## 10. Article Deduplication

Identification should use several signals:

1. stable RSS GUID or Atom identifier;
2. normalized canonical URL;
3. feed + URL combination;
4. fingerprint based on title, date, and content as a last resort.

URL normalization may remove some tracking parameters, but it must not aggressively merge two different pages.

Articles may be updated if the publisher corrects their title or content. The user state must not be lost during that update.

---

## 11. Authentication and Devices

### 11.1 Account

The MVP can use:

- email and password;
- password hashing with Argon2id;
- short-lived access token;
- revocable refresh token;
- optional email verification in the first private version.

### 11.2 Device Management

Each session should be linked to a device visible in the account:

```text
Android phone - last synced 5 min ago
Windows PC - last synced yesterday
Linux laptop - last synced 12 days ago
```

The user must be able to:

- rename a device;
- revoke its session;
- see its last sync time;
- delete the associated server data if needed.

### 11.3 Secret Storage

Tokens must not be stored in plaintext in SQLite. Use the secure storage available on each platform through a compatible Flutter package.

---

## 12. Security

Minimum requirements:

- HTTPS mandatory outside local development;
- strict input validation;
- parameterized SQL queries;
- rate limiting on authentication and RSS fetches;
- refresh token rotation and revocation;
- HTML sanitization for articles;
- maximum size for feeds and media;
- network timeouts;
- SSRF protection for the RSS collector;
- rejection of dangerous URL schemes;
- secrets only in environment variables;
- no secrets in Git or logs;
- documented PostgreSQL backups;
- monitored and updated dependencies.

The RSS collector must not be able to freely access `localhost`, private ranges, cloud metadata endpoints, or other internal services via a user-supplied URL.

---

## 13. Privacy

The project should adopt minimal data collection:

- do not sell data;
- do not include intrusive telemetry by default;
- document any optional telemetry;
- allow subscription export;
- provide account and data deletion;
- explain which data is kept on the server;
- allow local usage and self-hosted installation.

A separate privacy policy will be needed if a public instance is offered.

---

## 14. User Interface

### 14.1 Main Screens

- home or inbox;
- feeds and folders list;
- articles list;
- article reader;
- unread articles;
- favorites;
- add feed;
- OPML import/export;
- offline settings;
- synchronization settings;
- account and devices;
- sync diagnostics.

### 14.2 Android

- bottom navigation or side drawer;
- touch-friendly gestures;
- portrait and landscape modes;
- eventually share a URL into the app;
- discreet synchronization indicator;
- accessibility and system font scaling.

### 14.3 Desktop

Recommended three-column layout:

```text
[ Feeds and folders ] [ Articles list ] [ Article content ]
```

Plan for:

- responsive resizing;
- keyboard shortcuts;
- context menus;
- possible multi-selection;
- opening links in the default browser;
- visible hover and focus states.

### 14.4 States to Display

- synchronization in progress;
- last successful synchronization;
- number of pending actions;
- content available or unavailable offline;
- feed error;
- no network;
- expired session;
- storage nearly full.

---

## 15. Search and Organization

### MVP

- filter by read/unread;
- filter by favorite;
- filter by feed;
- subscription folders;
- simple local search in titles.

### Future Enhancements

- SQLite FTS5 full-text search;
- labels;
- automatic rules;
- smart views;
- server-side search;
- archiving;
- saved filters.

---

## 16. Indicative Functional API

```text
POST   /v1/auth/register
POST   /v1/auth/login
POST   /v1/auth/refresh
POST   /v1/auth/logout

GET    /v1/devices
PATCH  /v1/devices/:id
DELETE /v1/devices/:id

GET    /v1/subscriptions
POST   /v1/subscriptions
PATCH  /v1/subscriptions/:id
DELETE /v1/subscriptions/:id

GET    /v1/articles
GET    /v1/articles/:id

POST   /v1/sync/push
GET    /v1/sync/pull

POST   /v1/opml/import
GET    /v1/opml/export

GET    /health/live
GET    /health/ready
```

The API should be versioned from the start, at minimum with the `/v1` prefix.

---

## 17. Indicative Server Model

Main entities:

- `users`;
- `devices`;
- `sessions`;
- `feeds`;
- `feed_fetch_history`;
- `articles`;
- `subscriptions`;
- `folders`;
- `article_states`;
- `accepted_operations`;
- `change_log`;
- `sync_cursors` or equivalent state;
- `tombstones` if kept separate from the log.

Essential constraints:

- uniqueness of the normalized email;
- uniqueness of a feed's canonical URL;
- uniqueness of an article identifier within its feed;
- uniqueness of an operation per user and `operation_id`;
- indexes on cursors, publication dates, and unread states;
- cascading deletion only when it is genuinely intended.

---

## 18. GitHub Repository Organization

```text
open-rss-reader/
|-- apps/
|   `-- reader/
|       |-- lib/
|       |   |-- app/
|       |   |-- core/
|       |   |-- database/
|       |   |-- features/
|       |   |-- rss/
|       |   |-- sync/
|       |   `-- ui/
|       |-- android/
|       |-- windows/
|       |-- linux/
|       `-- test/
|-- server/
|   |-- src/
|   |   |-- auth/
|   |   |-- devices/
|   |   |-- feeds/
|   |   |-- articles/
|   |   |-- sync/
|   |   `-- workers/
|   |-- migrations/
|   `-- test/
|-- docs/
|   |-- architecture.md
|   |-- sync-protocol.md
|   |-- self-hosting.md
|   `-- contributing.md
|-- .github/
|   |-- workflows/
|   |-- ISSUE_TEMPLATE/
|   `-- pull_request_template.md
|-- docker-compose.yml
|-- .env.example
|-- LICENSE
|-- CONTRIBUTING.md
|-- CODE_OF_CONDUCT.md
|-- SECURITY.md
`-- README.md
```

A monorepo is a good fit because the client, API, and documentation evolve together.

---

## 19. License and Open-Source Governance

### 19.1 MIT License

The repository will be published under the MIT license. It should contain a `LICENSE` file with:

- the official MIT license text;
- the year of first publication;
- the rights holder's name.

Each dependency must have a license compatible with the intended distribution. Special attention is needed for parsing libraries, HTML sanitizers, content extraction tools, and icons.

### 19.2 Community Documentation

Plan for:

- `README.md`: presentation, screenshots, installation, and quick start;
- `CONTRIBUTING.md`: environment, conventions, tests, and pull requests;
- `CODE_OF_CONDUCT.md`: community rules;
- `SECURITY.md`: private vulnerability reporting;
- issue templates for bugs and feature requests;
- a pull request template;
- a changelog or release notes.

### 19.3 Contributions

Contributions should not require an exclusive copyright transfer. A Developer Certificate of Origin can be considered later, but it is not required to start.

---

## 20. Configuration and Self-Hosting

The server should be runnable with Docker Compose:

```text
services:
  api
  worker
  postgres
```

Configuration via environment variables:

```text
DATABASE_URL
JWT_SECRET or signing keys
ACCESS_TOKEN_TTL
REFRESH_TOKEN_TTL
PUBLIC_BASE_URL
RSS_FETCH_INTERVAL
RSS_MAX_RESPONSE_SIZE
LOG_LEVEL
CORS_ALLOWED_ORIGINS
```

Real values must never be committed. A documented `.env.example` is required.

---

## 21. Distribution and Updates

### Android

- signed APK for GitHub Releases;
- AAB if publishing on Google Play;
- separate development channel;
- clear policy for keeping local data during updates.

### Windows

- build performed on Windows;
- portable archive possible initially;
- MSIX or EXE installer in the long term;
- code signing recommended for broad distribution.

### Linux

- build performed on Linux;
- AppImage or archive for the MVP;
- DEB and Flatpak are possible later;
- supported architectures must be documented.

### GitHub Actions

On tag creation:

```text
v1.0.0
|-- Flutter tests
|-- server tests
|-- APK build
|-- Windows build
|-- Linux build
|-- checksum generation
`-- GitHub Release publication
```

Desktop builds are usually produced on their target system through a CI matrix.

---

## 22. Quality and Tests

### 22.1 Client

- unit tests for the synchronization engine;
- SQLite migration tests;
- local repository tests;
- widget tests;
- offline/online integration tests;
- tests on Android, Windows, and Linux;
- tests for recovery after forced closure.

### 22.2 Server

- unit tests for parsing and normalization;
- integration tests with PostgreSQL;
- idempotence tests;
- concurrency tests;
- journal pagination tests;
- authentication and revocation tests;
- SSRF and URL validation tests;
- migration tests.

### 22.3 Critical Scenarios

1. Read an article offline on Android, reconnect, then confirm the read state on Windows.
2. Perform two conflicting actions offline and verify the deterministic result.
3. Interrupt a synchronization in the middle of a batch, then resume without duplicates.
4. Reinstall a client and run a full synchronization.
5. Delete a subscription on one device while another stays offline.
6. Receive the same operation twice without a double effect.
7. Update the SQLite schema without losing local data.
8. Exceed the cache limit and preserve favorites/unread items.
9. Revoke a device and confirm it can no longer synchronize.
10. Receive a malformed feed or a page containing dangerous HTML.

---

## 23. Observability

The server should provide:

- structured logs;
- request identifiers;
- RSS fetch metrics;
- synchronization error rates;
- request duration;
- batch sizes;
- health endpoints;
- no sensitive content or tokens in logs.

The client should offer a diagnostics page containing:

- app version;
- anonymized device identifier;
- last cursor;
- last successful sync;
- number of pending operations;
- SQLite and cache sizes;
- exportable recent errors without secrets.

---

## 24. Expected Performance

Indicative MVP goals:

- usable launch within a few seconds on a typical device;
- smooth navigation with tens of thousands of local articles;
- paginated or virtualized lists;
- no heavy parsing on the UI thread;
- configurable synchronization batches, for example 100 to 500 changes;
- progressive image loading;
- SQLite indexes adapted to common filters;
- no full resynchronization during normal operation.

---

## 25. Accessibility and Internationalization

- keyboard-usable interface on desktop;
- visible focus states;
- labels accessible to screen readers;
- respect for text scaling;
- sufficient contrast;
- light, dark, and system themes;
- localized dates and numbers;
- architecture ready for French and English;
- avoid concatenating translated sentence fragments.

---

## 26. Roadmap

### Phase 0 - Framing

- choose the project name;
- create the MIT GitHub repository;
- write the architecture decisions;
- initialize Flutter, Node.js, and PostgreSQL;
- configure linting, tests, and CI.

### Phase 1 - Local Reader

- add a feed;
- parse RSS and Atom;
- store feeds and articles in SQLite;
- display the list and the reader;
- mark read/unread and favorite;
- work fully offline after download.

### Phase 2 - Cache and UX

- download images;
- apply the retention policy;
- expose offline settings;
- adapt the Android/desktop UI;
- add OPML support.

### Phase 3 - Server

- accounts and sessions;
- PostgreSQL and migrations;
- centralized subscriptions;
- RSS fetch worker;
- device management.

### Phase 4 - Synchronization

- local operation queue;
- idempotent push;
- change log;
- cursor-based pull;
- conflicts and tombstones;
- controlled full resynchronization.

### Phase 5 - Distribution

- Android, Windows, and Linux builds;
- multi-OS GitHub Actions;
- Docker Compose;
- self-hosting documentation;
- signed GitHub Releases or releases with checksums.

### Phase 6 - Enhancements

- full-text search;
- optional full-article extraction;
- notifications;
- web portal;
- iOS/macOS;
- sharing;
- smart rules and views.

---

## 27. Recommended MVP

The MVP is considered complete when:

- the app works on Android and at least one desktop platform;
- a user can add an RSS or Atom feed;
- articles are stored locally;
- downloaded articles are readable without a connection;
- read/unread and favorite states work offline;
- two devices can connect to the same account;
- offline actions synchronize after reconnection;
- replaying an operation does not create duplicates;
- conflicts produce a deterministic result;
- the user can import and export an OPML file;
- the server can be launched with Docker Compose;
- the repository contains the MIT license and installation instructions;
- tests cover the critical synchronization scenarios.

---

## 28. Detailed Acceptance Criteria

### Offline Reading

**Given** that an article has been downloaded, **when** the device loses the network, **then** its title, available content, and cached media remain accessible.

### Offline Action

**Given** that the device is offline, **when** the user marks an article as read, **then** the UI updates immediately and the operation stays queued.

### Multi-Device Synchronization

**Given** that an article was read on Android, **when** Android then Windows synchronize, **then** Windows shows that article as read.

### Resume

**Given** that synchronization was interrupted, **when** it resumes, **then** no action is lost or applied twice.

### Cache Cleanup

**Given** that the storage limit is reached, **when** cleanup runs, **then** older read media are removed first and favorites/unread items are preserved.

### Revocation

**Given** that a device has been revoked, **when** it tries to refresh its session or synchronize, **then** the server rejects the operation and the app informs the user.

---

## 29. Proposed Technical Decisions

| Domain | Initial Choice |
|---|---|
| Client | Flutter/Dart |
| Client architecture | Features + repositories + services, with UI/domain/data separation |
| Local database | SQLite via Drift |
| API | Node.js TypeScript with Fastify |
| Server database | PostgreSQL |
| Server migrations | Tool chosen with the ORM/query builder |
| RSS worker | Separate Node.js process or worker in the monorepo |
| Authentication | Short-lived access token + revocable refresh token |
| Deployment | Docker Compose |
| CI/CD | GitHub Actions |
| License | MIT |
| Synchronization | Operation log + server cursor |
| MVP conflicts | Last operation ordered by the server |
| Local media | File system + SQLite metadata |

These choices are starting points, not irreversible constraints. Any major change should be documented in an ADR under `docs/decisions/`.

---

## 30. Questions to Resolve Before Full Implementation

1. What project name should be used?
2. Should Windows or Android be the first demonstration platform?
3. Will the public instance be free, paid, or personal-only?
4. Is accountless mode mandatory from the first MVP?
5. What storage limit should be chosen by default?
6. Should images be downloaded automatically on mobile data?
7. Should display preferences be synchronized?
8. How long should tombstones and server changes be kept?
9. Should a device that stayed offline for a very long time perform a full resync?
10. What Linux distribution format should be prioritized first: AppImage, DEB, or Flatpak?
11. What policy should be used for full-content extraction?
12. Should public registration require email verification?

---

## 31. Starting Instructions for Codex

When generating the project from scratch:

1. do not implement every feature at once;
2. start with the Flutter local reader and SQLite migrations;
3. write tests for business logic before the synchronization server;
4. isolate UI from storage and networking;
5. model synchronization identifiers and operations from the start;
6. never make rendering depend on a direct network call;
7. verify Flutter package compatibility with Android, Windows, and Linux;
8. document structural decisions;
9. do not commit any secret;
10. keep changes small, testable, and readable.

### Suggested First Iteration

Create only:

- the cross-platform Flutter skeleton;
- the `Feed`, `Article`, and `ArticleState` models;
- the Drift database with its first migration;
- a local repository;
- manual RSS URL addition;
- parsing and persistence;
- a feed list;
- an article list;
- a simple reader;
- read/unread and favorite actions;
- the corresponding tests.

The server and remote synchronization should come later, once local behavior is reliable.

---

## 32. Architectural Summary

The project is a **local-first, offline-first, open-source, self-hostable RSS reader**.

- Flutter produces the Android APK and the Windows/Linux desktop apps.
- SQLite stores the data needed for daily use.
- Offline media are kept as local files.
- Node.js and PostgreSQL synchronize accounts and devices.
- Offline actions are recorded in a persistent queue.
- The server accepts operations idempotently.
- Clients fetch changes through a cursor.
- Conflicts follow deterministic rules.
- GitHub Actions builds deliverables on the appropriate systems.
- The repository is distributed under the MIT license and documents self-hosting.

The highest priority remains: **the user must be able to read and organize articles even if the Internet or the server is unavailable, without losing actions that will be synchronized later.**
