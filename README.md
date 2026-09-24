# Sift — Native macOS RSS Reader

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-blue.svg)](https://apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange.svg)](https://swift.org)
[![SwiftData](https://img.shields.io/badge/Persistence-SwiftData-green.svg)](https://developer.apple.com/xcode/swiftdata/)
[![License](https://img.shields.io/badge/License-MIT-brightgreen.svg)](LICENSE)
[![Languages](https://img.shields.io/badge/Languages-EN%20%7C%20TR%20%7C%20DE%20%7C%20FR-purple.svg)](#localization)

**Sift** is a lightweight, privacy-focused, native macOS RSS and Atom feed reader built with **SwiftUI**, **SwiftData**, and **WidgetKit**. It offers a clean 3-column desktop layout, customizable reader typography, background feed synchronization, OPML backup/import, auto-discovery of feeds from web pages, and WidgetKit extension integration.

---

## 💡 Key Features

- **⚡ Native & Fast**: Built natively for macOS using SwiftData and SwiftUI for maximum performance and low memory footprint.
- **🖥️ 3-Column Modern UI**: Sidebar with customizable feed folders, article list with live search, and clean article detail view.
- **📖 Dual Reading Modes**:
  - **Reader Mode**: Clean, distraction-free reading experience with customizable typography (font size, font family: System, Serif, Monospace).
  - **In-App Web Mode**: Full `WKWebView` wrapper to view the original web page directly inside the app.
- **🔍 Auto Feed Discovery**: Type or paste any website URL (e.g. `example.com`), and Sift automatically extracts `<link rel="alternate">` RSS/Atom feed URLs.
- **📁 Feed Folders & Categories**: Organize your feeds into custom folders with context menu categorization.
- **🏷️ Smart Filters**: Quick access to **All Articles**, **Today**, **This Week**, **Unread**, and **Starred** items.
- **📦 OPML Import & Export**: Import your existing subscriptions from NetNewsWire, Reeder, Feedly, or export backups anytime.
- **⏱️ Reading Duration & PDF Export**:
  - Displays estimated reading time (e.g. `3 min read`).
  - Native macOS printing and PDF export (`⌘ + P`).
- **🔔 macOS Background Refresh & Notifications**: Automatic background synchronization using `BackgroundFeedScheduler` and macOS system notifications for new articles.
- **🧩 WidgetKit Integration**: Interactive desktop & Notification Center widgets showing unread article counts and latest headlines with deep-link support (`rssreader://`).
- **⌨️ Keyboard Shortcuts**:
  - `J` / `K`: Navigate to Next / Previous article
  - `M`: Toggle Read / Unread status
  - `S`: Toggle Starred status
  - `O`: Open article in default external browser
  - `⌘ + R`: Refresh all feeds
- **🌍 Localization**: Fully localized in **English (en)**, **Turkish (tr)**, **German (de)**, and **French (fr)**.

---

## 🏗️ Architecture & Documentation

Detailed architectural documentation is available in the [`docs/`](docs/) directory:

- [📄 Architecture Overview (`docs/ARCHITECTURE.md`)](docs/ARCHITECTURE.md) — Describes the application architecture, SwiftData models, HTTP layer, background scheduling, App Group integration, and WidgetKit extension.
- [📄 Data Flow Diagram (`docs/DATA_FLOW.md`)](docs/DATA_FLOW.md) — Explains the end-to-end data flow between network fetching, feed parsing, SwiftData persistence, UI state management, and Widget snapshots.

---

## 🛠️ Building & Running

### Requirements
- **macOS**: 14.0 (Sonoma) or later
- **Xcode**: 15.0 or later
- **Swift**: 5.9 or later

### Setup Instructions
1. Clone the repository:
   ```bash
   git clone https://github.com/your-username/Sift.git
   cd Sift
   ```
2. Open the Xcode project:
   ```bash
   open Sift.xcodeproj
   ```
3. Select the `Sift` target and run (`⌘ + R`).

---

## 🌐 Localization

Sift supports string catalog localization (`Localizable.xcstrings`) for:
- 🇺🇸 **English** (`en`)
- 🇹🇷 **Turkish** (`tr`)
- 🇩🇪 **German** (`de`)
- 🇫🇷 **French** (`fr`)

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
