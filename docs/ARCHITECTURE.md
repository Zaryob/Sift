# Sift Architecture Overview

Sift is a lightweight, native macOS RSS and Atom feed reader built with modern Apple frameworks.

## Process Architecture & App Lifecycle

Sift runs as a single primary macOS process supporting background feed synchronization, menu bar presence, and a native 3-column main window.

- **Main Application**: Built using SwiftUI, SwiftData, Observation (`@Observable`), and Swift Concurrency.
- **Background Execution**: Operates via `BackgroundFeedScheduler` which continues periodic polling using Swift structured concurrency (`Task`) even when all application main windows are closed.
- **Launch at Login**: Integrates with Apple's `SMAppService.mainApp` API allowing the application to register/unregister as a login item without requiring deprecated helper binaries or root daemons.
- **Menu Bar Extra**: Provides quick controls, unread counts, background status, and window restoration via `MenuBarExtra`.

## Feed Refresh Lifecycle & Algorithm

Feed updates operate via HTTP conditional requests:

1. **Trigger**: Manual user refresh, background periodic timer, or app startup.
2. **Concurrency**: Managed by `FeedRefreshService` actor with bounded concurrency (maximum 4 simultaneous requests).
3. **HTTP Polling & Headers**:
   - `If-None-Match`: Sends persisted `ETag`.
   - `If-Modified-Since`: Sends persisted `Last-Modified`.
   - Compression: Accepts gzip/deflate via `URLSession`.
   - Custom Browser `User-Agent`: Resolves requests against protected web hosts.
   - Request Timeout: 15 seconds limit per feed.
4. **HTTP 304 Handling**: If server responds with `304 Not Modified`, networking completes cleanly without downloading or parsing payload.
5. **Defensive Parsing**: Handled by `FeedParser` conforming to `XMLParserDelegate`. Supports RSS 2.0 and Atom feeds. Parser isolates malformed items so valid items are imported even if one item is invalid.
6. **Auto Feed Discovery**: Handled by `FeedDiscoveryService`. If user inputs a website URL, the service fetches HTML, scans for `<link rel="alternate" type="application/rss+xml">` or `application/atom+xml` tags, resolves relative URLs, and auto-discovers feed endpoints.
7. **Deduplication Order**:
   - Primary: RSS/Atom `GUID` / `ID`
   - Secondary: Article canonical URL (`link`)
   - Fallback: Deterministic key derived from `(FeedID + Title + PublicationDate)`
8. **Storage & Notification**: Saves updated metadata (`lastSuccessfulRefresh`, `etag`, `lastModified`) and new `FeedItem` entities to SwiftData, sends macOS User Notifications via `NotificationManager`, updates Widget snapshot, and calls `WidgetCenter.shared.reloadAllTimelines()`.

## SwiftData Storage & App Group Design

- **Authoritative Source of Truth**: Single SwiftData store backed by `@Model` entities (`Feed` and `FeedItem`).
- **App Group**: Shared directory configuration under `group.com.sift.app`.
- **Widget Snapshot**: `WidgetSnapshotManager` serializes a lightweight JSON snapshot (`recent_articles.json`) of recent articles into the App Group directory whenever feeds refresh.
- **Widget Read Performance**: The WidgetKit extension (`SiftWidgetExtension`) reads directly from this lightweight JSON snapshot, guaranteeing sub-millisecond timeline reloads without database locks or concurrency conflicts.

## Additional Features & Localization

- **OPML Backup & Import**: `OPMLService` handles parsing and generating standard OPML XML 2.0 files for migration.
- **Reader Typography & PDF Export**: Reader view font size and design preferences are saved via `@AppStorage`. Native printing and PDF saving is provided via `NSPrintOperation`.
- **String Catalog Localization**: Localized in English (`en`), Turkish (`tr`), German (`de`), and French (`fr`) via Xcode `Localizable.xcstrings`.

## Deep Link Routing

- **URL Scheme**: `rssreader://`
- **Supported Routes**:
  - `rssreader://all`: Selects "All Articles" view.
  - `rssreader://feed/<feed-uuid>`: Selects specific feed.
  - `rssreader://article/<article-uuid>`: Selects and highlights article in main app window.
- **Router**: `DeepLinkRouter` parses incoming `URL`s and directs state in `AppViewModel`.
