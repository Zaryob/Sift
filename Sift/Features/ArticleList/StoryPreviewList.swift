import SwiftUI
import SwiftData

struct StoryPreviewList: View {
    let groups: [StoryPreviewGroup]
    let categories: [StoryPreviewCategory]
    let articlesByID: [UUID: FeedItem]
    let unassignedIDs: [UUID]
    let metrics: StoryPreviewMetrics?
    let isBuilding: Bool
    let onEnrichmentPassComplete: () -> Void
    @Binding var selectedArticle: FeedItem?
    @ObservedObject private var enrichmentQueue = ArticleEnrichmentQueue.shared
    @State private var selectedCategoryID: String?

    var body: some View {
        let dateWindow = StoryPreviewDateWindow()
        let recentArticleIDs = Set(
            articlesByID.values.lazy
                .filter { dateWindow.contains($0.publicationDate) }
                .map(\.id)
        )
        let recentGroups = groups.compactMap { group -> StoryPreviewGroup? in
            let articleIDs = group.articleIDs.filter { recentArticleIDs.contains($0) }
            guard !articleIDs.isEmpty else { return nil }
            return StoryPreviewGroup(
                id: group.id,
                articleIDs: articleIDs,
                publisherCount: min(group.publisherCount, articleIDs.count)
            )
        }
        let recentUnassignedIDs = unassignedIDs.filter { recentArticleIDs.contains($0) }
        let recentCategories = categories.compactMap { category -> StoryPreviewCategory? in
            let groupIDs = category.storyGroupIDs.filter { groupID in
                recentGroups.contains { $0.id == groupID }
            }
            let articleIDs = category.articleIDs.filter { recentArticleIDs.contains($0) }
            guard !groupIDs.isEmpty || !articleIDs.isEmpty else { return nil }
            return StoryPreviewCategory(
                id: category.id,
                title: category.title,
                storyGroupIDs: groupIDs,
                articleIDs: articleIDs
            )
        }
        let selectedCategory = recentCategories.first { $0.id == selectedCategoryID }
        let visibleGroups = selectedCategory.map { category in
            recentGroups.filter { category.storyGroupIDs.contains($0.id) }
        } ?? recentGroups
        let visibleUnassignedIDs = selectedCategory?.articleIDs ?? recentUnassignedIDs

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

            if enrichmentQueue.isProcessing {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        if let progressMessage = enrichmentQueue.progressMessage {
                            Text(progressMessage)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Enriching recent articles on this device…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
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

            if !recentCategories.isEmpty {
                Section {
                    StoryPreviewCategoryFilter(
                        categories: recentCategories,
                        selection: $selectedCategoryID
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } header: {
                    Text("Topics from recent coverage")
                        .textCase(nil)
                } footer: {
                    Text("Topic labels come from on-device article digests and may change as more recent articles are enriched.")
                }
            }

            ForEach(visibleGroups) { group in
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

            if !visibleUnassignedIDs.isEmpty {
                Section {
                    ForEach(visibleUnassignedIDs, id: \.self) { id in
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

            if !isBuilding, recentGroups.isEmpty, recentUnassignedIDs.isEmpty {
                ContentUnavailableView(
                    "No Recent Articles",
                    systemImage: "square.stack.3d.up",
                    description: Text("Refresh your feeds to build a preview from articles published today and yesterday.")
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationLinkIndicatorVisibility(.hidden)
        .onChange(of: enrichmentQueue.completedPassCount) { _, count in
            guard count > 0 else { return }
            onEnrichmentPassComplete()
        }
    }
}

private struct StoryPreviewCategoryFilter: View {
    let categories: [StoryPreviewCategory]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                StoryPreviewCategoryChip(
                    title: nil,
                    isSelected: selection == nil || !categories.contains { $0.id == selection },
                    action: { selection = nil }
                )
                ForEach(categories) { category in
                    StoryPreviewCategoryChip(
                        title: category.title,
                        isSelected: selection == category.id,
                        action: { selection = category.id }
                    )
                }
            }
            .padding(.vertical, 3)
        }
        .scrollIndicators(.hidden)
    }
}

private struct StoryPreviewCategoryChip: View {
    let title: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if let title {
                    Text(title)
                } else {
                    Text("All stories")
                }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background {
                Capsule()
                    .fill(isSelected ? Color.siftAccent : Color.secondary.opacity(0.12))
            }
        }
        .buttonStyle(.plain)
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

            if metrics.enrichedArticleCount > 0 {
                Text("\(metrics.enrichedArticleCount) article digests · \(metrics.dailyCategoryCount) daily topics")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Daily topics appear as Apple Intelligence prepares article digests on this device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
            "M0 quality gate not passed. Article digests and topic labels are experimental; story-level summaries are not generated."
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
