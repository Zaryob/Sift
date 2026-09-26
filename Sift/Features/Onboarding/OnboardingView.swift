import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let viewModel: AppViewModel

    @State private var selectedPackTitles: Set<String> = Set(StarterPack.allPacks.map(\.title))
    @State private var isSubscribing: Bool = false
    @State private var isShowingFileImporter: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "newspaper.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.siftAccent)
                        .padding(.top, 24)

                    Text("Welcome to Sift")
                        .font(.title.weight(.bold))

                    Text("Get started by choosing curated reading packs, or import your existing subscriptions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .padding(.bottom, 20)

                // List of Starter Packs
                List {
                    Section("Recommended Starter Packs") {
                        ForEach(StarterPack.allPacks) { pack in
                            StarterPackRow(
                                pack: pack,
                                isSelected: selectedPackTitles.contains(pack.title),
                                onToggle: {
                                    if selectedPackTitles.contains(pack.title) {
                                        selectedPackTitles.remove(pack.title)
                                    } else {
                                        selectedPackTitles.insert(pack.title)
                                    }
                                }
                            )
                        }
                    }

                    Section {
                        Button {
                            isShowingFileImporter = true
                        } label: {
                            Label("Import Subscriptions from OPML…", systemImage: "square.and.arrow.down")
                                .font(.body.weight(.medium))
                        }
                    } footer: {
                        Text("Already using NetNewsWire, Reeder, or Feedly? Bring all your feeds with an OPML file.")
                    }
                }
                #if os(macOS)
                .listStyle(.inset(alternatesRowBackgrounds: true))
                #else
                .listStyle(.insetGrouped)
                #endif

                // Bottom Action Bar
                VStack(spacing: 12) {
                    Button {
                        subscribeToSelectedPacks()
                    } label: {
                        HStack {
                            if isSubscribing {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, 4)
                            }
                            Text(actionButtonTitle)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.siftAccent)
                    .disabled(isSubscribing)

                    Button("Skip for Now") {
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .background(.bar)
            }
            #if os(macOS)
            .frame(width: 480, height: 560)
            #endif
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.xml, .plainText],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let url) = result {
                    Task {
                        await viewModel.importOPMLFile(at: url, context: modelContext)
                        dismiss()
                    }
                }
            }
        }
    }

    private var actionButtonTitle: String {
        let count = selectedPackTitles.count
        if count == 0 {
            return String(localized: "Start with Empty Library")
        } else {
            let totalFeeds = StarterPack.allPacks
                .filter { selectedPackTitles.contains($0.title) }
                .reduce(0) { $0 + $1.feeds.count }
            return String(localized: "Subscribe to \(totalFeeds) Feeds")
        }
    }

    private func subscribeToSelectedPacks() {
        isSubscribing = true
        let chosenPacks = StarterPack.allPacks.filter { selectedPackTitles.contains($0.title) }

        for pack in chosenPacks {
            for item in pack.feeds {
                let feed = Feed(title: item.title, url: item.url, category: item.category)
                modelContext.insert(feed)
            }
        }

        try? modelContext.save()
        viewModel.refreshAllFeeds(context: modelContext)
        isSubscribing = false
        dismiss()
    }
}

struct StarterPackRow: View {
    let pack: StarterPack
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: pack.iconName)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.siftAccent)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pack.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)

                    Text(pack.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isSelected ? Color.siftAccent : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
