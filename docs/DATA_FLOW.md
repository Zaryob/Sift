# Sift Data Flow Documentation

This document describes the key end-to-end data flows within Sift.

## 1. Background Feed Synchronization Flow

```mermaid
graph TD
    A["macOS User Login / Periodic Timer"] --> B["BackgroundFeedScheduler"]
    B --> C["FeedRefreshService (Actor)"]
    C --> D["URLSession (Conditional GET with ETag / Last-Modified)"]
    D -->|200 OK + XML Data| E["FeedParser (RSS 2.0 / Atom Parser)"]
    D -->|304 Not Modified| F["Update lastSuccessfulRefresh in SwiftData"]
    E --> G["Normalized FeedItem Values"]
    G --> H["Deduplication (GUID -> Link -> Fallback)"]
    H --> I["Persist New Items in SwiftData"]
    I --> J["WidgetSnapshotManager (Export JSON to App Group)"]
    J --> K["WidgetCenter.shared.reloadAllTimelines()"]
    K --> L["WidgetKit Extension Reloads UI"]
```

## 2. Widget Interaction & Deep Link Flow

```mermaid
graph TD
    A["User Clicks Article in macOS Widget"] --> B["URL Scheme: rssreader://article/&lt;article-id&gt;"]
    B --> C["macOS Launches or Activates Sift Application"]
    C --> D["ContentView onOpenURL(url)"]
    D --> E["DeepLinkRouter.parse(url)"]
    E --> F["AppViewModel Resolves Article and Parent Feed"]
    F --> G["Main Window Selects Feed & Highlights Article"]
```

## 3. External Article Reading Flow

```mermaid
graph TD
    A["User Double-Clicks Article in Article List or Clicks 'Open in Browser'"] --> B["AppViewModel.openArticleExternally(article)"]
    B --> C["Extract article.link URL"]
    C --> D["NSWorkspace.shared.open(url)"]
    D --> E["Default macOS Browser (Safari/Chrome/Firefox) Opens Original Webpage"]
```

## 4. Add Feed User Flow

```mermaid
graph TD
    A["User Clicks '+' Button in Sidebar"] --> B["AddFeedSheet Presented"]
    B --> C["User Inputs RSS/Atom URL"]
    C --> D["FeedHTTPClient Fetches Feed"]
    D --> E["FeedParser Validates & Extracts Metadata"]
    E -->|Valid RSS/Atom| F["Insert Feed & Initial FeedItems into SwiftData"]
    E -->|Malformed / Invalid URL| G["Display Informative Error Alert"]
```
