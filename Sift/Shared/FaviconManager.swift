import Foundation
import SwiftUI
import Combine
import CryptoKit

/// Thread-safe, persistent local favicon & logo manager.
/// Features:
/// 1. Fast in-memory cache (NSCache) for zero-latency 60/120fps scrolling.
/// 2. Local disk cache in Caches/Favicons directory for offline and cross-launch persistence.
/// 3. In-flight request deduplication: multiple list items requesting the same favicon share ONE network task.
/// 4. Negative caching: failed or 404 endpoints are remembered to prevent repeated network spam.
@MainActor
public final class FaviconManager: ObservableObject {
    public static let shared = FaviconManager()

    private let memoryCache = NSCache<NSString, PlatformImage>()
    private var inFlightTasks: [String: Task<PlatformImage?, Never>] = [:]
    private var failedURLs: Set<String> = []

    private let cacheDirectory: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = caches.appendingPathComponent("Favicons", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }()

    private init() {
        memoryCache.countLimit = 250
    }

    // MARK: - Synchronous Local Lookup (Memory -> Disk)

    /// Returns the cached image immediately if available in memory or on disk.
    /// Does NOT trigger any network request.
    public func cachedImage(for feed: Feed) -> PlatformImage? {
        guard let url = FaviconFetcher.faviconURL(for: feed.siteURL, feedURLString: feed.url, iconURLString: feed.iconURL) else {
            return nil
        }
        return cachedImage(for: url)
    }

    /// Returns the cached image immediately if available in memory or on disk for a given URL.
    public func cachedImage(for url: URL) -> PlatformImage? {
        let key = cacheKey(for: url)

        // 1. Check in-memory cache
        if let memoryImage = memoryCache.object(forKey: key as NSString) {
            return memoryImage
        }

        // 2. Check disk cache
        if let diskImage = loadFromDisk(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString)
            return diskImage
        }

        return nil
    }

    // MARK: - Asynchronous Fetch with Deduplication

    /// Fetches the favicon for a feed, returning from cache if already downloaded,
    /// or deduplicating against any existing in-flight download.
    public func fetchFavicon(for feed: Feed) async -> PlatformImage? {
        guard let url = FaviconFetcher.faviconURL(for: feed.siteURL, feedURLString: feed.url, iconURLString: feed.iconURL) else {
            return nil
        }
        return await fetchFavicon(for: url)
    }

    /// Fetches the favicon for a URL, returning from cache if already downloaded,
    /// or deduplicating against any existing in-flight download.
    public func fetchFavicon(for url: URL) async -> PlatformImage? {
        let key = cacheKey(for: url)
        let urlString = url.absoluteString

        // 1. Check local caches first
        if let cached = cachedImage(for: url) {
            return cached
        }

        // 2. Check negative cache (skip known failures)
        if failedURLs.contains(urlString) {
            return nil
        }

        // 3. Deduplicate against in-flight network requests
        if let existingTask = inFlightTasks[key] {
            return await existingTask.value
        }

        // 4. Start single shared network task
        let task = Task<PlatformImage?, Never> { [weak self] () -> PlatformImage? in
            defer {
                Task { @MainActor [weak self] in
                    self?.inFlightTasks.removeValue(forKey: key)
                }
            }

            var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
            request.setValue("Sift RSS Reader", forHTTPHeaderField: "User-Agent")

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = PlatformImage(data: data) else {
                await MainActor.run {
                    self?.failedURLs.insert(urlString)
                }
                return nil
            }

            // Save to disk & memory cache
            await MainActor.run {
                self?.saveToDisk(data: data, key: key)
                self?.memoryCache.setObject(image, forKey: key as NSString)
                self?.objectWillChange.send()
            }

            return image
        }

        inFlightTasks[key] = task
        return await task.value
    }

    /// Fetches raw image data for local use (e.g. UNNotificationAttachment).
    public func faviconData(for url: URL) async -> Data? {
        let key = cacheKey(for: url)
        if let fileURL = diskFileURL(key: key),
           FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL) {
            return data
        }

        // Fetch image first to populate cache
        _ = await fetchFavicon(for: url)

        if let fileURL = diskFileURL(key: key),
           let data = try? Data(contentsOf: fileURL) {
            return data
        }
        return nil
    }

    /// Prefetches favicons in the background for a collection of feeds.
    public func prefetchFavicons(for feeds: [Feed]) {
        for feed in feeds {
            Task {
                _ = await self.fetchFavicon(for: feed)
            }
        }
    }

    /// Clears both memory and disk caches, and resets failed URLs.
    public func clearCache() {
        memoryCache.removeAllObjects()
        failedURLs.removeAll()
        guard let cacheDirectory = cacheDirectory else { return }
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Disk Storage Helpers

    private func cacheKey(for url: URL) -> String {
        let hash = SHA256.hash(data: Data(url.absoluteString.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func diskFileURL(key: String) -> URL? {
        cacheDirectory?.appendingPathComponent("\(key).img")
    }

    private func loadFromDisk(key: String) -> PlatformImage? {
        guard let fileURL = diskFileURL(key: key),
              FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return PlatformImage(data: data)
    }

    private func saveToDisk(data: Data, key: String) {
        guard let fileURL = diskFileURL(key: key) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
