import SwiftUI

public struct FeedFaviconView: View {
    public let feed: Feed?
    public let customURL: URL?
    public var title: String = ""
    public var size: CGFloat = 16
    public var cornerRadius: CGFloat = 4

    @State private var image: PlatformImage?

    public init(feed: Feed, size: CGFloat = 16, cornerRadius: CGFloat? = nil) {
        self.feed = feed
        self.customURL = nil
        self.title = feed.title
        self.size = size
        self.cornerRadius = cornerRadius ?? size * 0.22
        let cached = FaviconManager.shared.cachedImage(for: feed)
        self._image = State(initialValue: cached)
    }

    public init(url: URL?, size: CGFloat = 16, cornerRadius: CGFloat? = nil) {
        self.feed = nil
        self.customURL = url
        self.title = ""
        self.size = size
        self.cornerRadius = cornerRadius ?? size * 0.22
        let cached = url.flatMap { FaviconManager.shared.cachedImage(for: $0) }
        self._image = State(initialValue: cached)
    }

    public init(title: String, size: CGFloat = 16, cornerRadius: CGFloat? = nil) {
        self.feed = nil
        self.customURL = nil
        self.title = title
        self.size = size
        self.cornerRadius = cornerRadius ?? size * 0.22
        self._image = State(initialValue: nil)
    }

    public var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                placeholderIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .task(id: feed?.id.uuidString ?? customURL?.absoluteString ?? title) {
            loadFavicon()
        }
    }

    private func loadFavicon() {
        if let feed {
            // 1. Instant Synchronous Fast Path from Cache (0ms latency, zero flicker)
            if let cached = FaviconManager.shared.cachedImage(for: feed) {
                self.image = cached
                return
            }

            // 2. Asynchronous Fetch with Deduplication (single request shared across all items)
            Task {
                let fetched = await FaviconManager.shared.fetchFavicon(for: feed)
                if let fetched {
                    withAnimation(.easeIn(duration: 0.15)) {
                        self.image = fetched
                    }
                }
            }
        } else if let customURL {
            if let cached = FaviconManager.shared.cachedImage(for: customURL) {
                self.image = cached
                return
            }

            Task {
                let fetched = await FaviconManager.shared.fetchFavicon(for: customURL)
                if let fetched {
                    withAnimation(.easeIn(duration: 0.15)) {
                        self.image = fetched
                    }
                }
            }
        }
    }

    private var placeholderIcon: some View {
        let initialChar = (feed?.title.trimmingCharacters(in: .whitespacesAndNewlines) ?? title.trimmingCharacters(in: .whitespacesAndNewlines)).first
        return ZStack {
            Color.siftAccent.opacity(0.15)
            if let char = initialChar, char.isLetter || char.isNumber {
                Text(String(char).uppercased())
                    .font(.system(size: size * 0.52, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.siftAccent)
            } else {
                Image(systemName: "dot.radiowaves.up.forward")
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(Color.siftAccent)
            }
        }
    }
}
