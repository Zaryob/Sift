import SwiftUI
import SwiftData

struct StoryPreviewList: View {
    let groups: [StoryPreviewGroup]
    let articlesByID: [UUID: FeedItem]
    let unassignedIDs: [UUID]
    let metrics: StoryPreviewMetrics?
    let isBuilding: Bool
    @Binding var selectedArticle: FeedItem?

    var body: some View {
        List(selection: $selectedArticle) {
            if isBuilding {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Comparing recent coverage on this device…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .listRowSeparator(.hidden)
                }
            }

            if let metrics, metrics.analysisState != .noRecentArticles {
                Section {
                    StoryPreviewStatusCard(metrics: metrics)
                        .listRowSeparator(.hidden)
                }
            }

            ForEach(groups) { group in
                let memberArticles = group.articleIDs.compactMap { articlesByID[$0] }
                if let representative = memberArticles.first {
                    Section {
                        ForEach(memberArticles) { article in
                            NavigationLink(value: article) {
                                StoryPreviewSourceRow(article: article)
                            }
                            .tag(article)
                        }
                    } header: {
                        StoryPreviewGroupHeader(
                            title: representative.title,
                            articleCount: memberArticles.count,
                            publisherCount: group.publisherCount
                        )
                    }
                }
            }

            if !unassignedIDs.isEmpty {
                Section {
                    ForEach(unassignedIDs, id: \.self) { id in
                        if let article = articlesByID[id] {
                            NavigationLink(value: article) {
                                StoryPreviewSourceRow(article: article)
                            }
                            .tag(article)
                        }
                    }
                } header: {
                    Text(metrics?.analysisState == .modelUnavailable ? "Not analyzed" : "Not grouped")
                        .textCase(nil)
                } footer: {
                    Text(unassignedFooter)
                }
            }

            if !isBuilding, groups.isEmpty, unassignedIDs.isEmpty {
                ContentUnavailableView(
                    "No Recent Articles",
                    systemImage: "square.stack.3d.up",
                    description: Text("Refresh your feeds to build a preview from articles published in the last 72 hours.")
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationLinkIndicatorVisibility(.hidden)
    }
}

private struct StoryPreviewStatusCard: View {
    let metrics: StoryPreviewMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                metrics.analysisState == .modelUnavailable
                    ? "On-device analysis unavailable"
                    : "Experimental on-device preview",
                systemImage: metrics.analysisState == .modelUnavailable ? "exclamationmark.triangle" : "sparkles"
            )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.siftAccent)

            Text(statusDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Text("\(metrics.readyArticleCount) of \(metrics.analyzedArticleCount) articles analyzed · \(metrics.articleBodyCount) with substantial body text")
                .font(.caption)
                .foregroundStyle(.secondary)

            if metrics.waitingForTranslationCount > 0 || metrics.unsupportedLanguageCount > 0 || metrics.otherFailureCount > 0 {
                Text("\(metrics.waitingForTranslationCount) waiting for language assets · \(metrics.unsupportedLanguageCount) unsupported languages · \(metrics.otherFailureCount) other analysis limits")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusDescription: LocalizedStringResource {
        switch metrics.analysisState {
        case .completed:
            "M0 quality gate not passed. No summaries are generated; open a source article to inspect the reporting."
        case .modelUnavailable:
            "Apple's on-device embedding model did not load. This run did not evaluate whether these stories match."
        case .noRecentArticles:
            "There are no recent articles to analyze."
        }
    }
}

private extension StoryPreviewList {
    var unassignedFooter: LocalizedStringResource {
        if metrics?.analysisState == .modelUnavailable {
            return "These articles were not analyzed because the on-device embedding model could not load. This is not a negative story match."
        }
        return "These articles stayed separate because there was too little text, an unavailable language pair, or no usable on-device embedding."
    }
}

private struct StoryPreviewGroupHeader: View {
    let title: String
    let articleCount: Int
    let publisherCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .textCase(nil)

            Text("\(publisherCount) publishers · \(articleCount) source articles")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
        .padding(.top, 6)
        .padding(.bottom, 2)
    }
}

private struct StoryPreviewSourceRow: View {
    let article: FeedItem

    private var publisherTitle: String {
        article.feed?.title ?? article.author ?? String(localized: "Unknown source")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(publisherTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(article.publicationDate, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(article.title)
                .font(.body.weight(article.isRead ? .regular : .medium))
                .foregroundStyle(.primary)
                .lineLimit(3)

            if article.isStarred {
                Label("Saved", systemImage: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.siftStarred)
            }
        }
        .padding(.vertical, 4)
    }
}
