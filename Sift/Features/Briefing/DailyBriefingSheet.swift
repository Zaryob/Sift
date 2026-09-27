import SwiftUI
import SwiftData

/// Dedicated sheet presenting an on-device Apple Intelligence news briefing.
public struct DailyBriefingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var intelligence = ArticleIntelligenceService.shared
    @ObservedObject private var speaker = ArticleSpeaker.shared

    @State private var briefingText: String = ""
    @State private var isGenerating: Bool = false
    @State private var modelKind: IntelligenceModelKind?
    @State private var isCached: Bool = false

    private let briefingID = UUID()

    public init() {}

    private var isPlayingBriefing: Bool {
        speaker.isSpeaking && speaker.currentArticleID == briefingID
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Header card
                        HStack(alignment: .center, spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.siftAccent, Color.purple.opacity(0.8)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 44, height: 44)

                                Image(systemName: "sparkles")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Spoken Briefing")
                                    .font(.headline)
                                if let modelKind {
                                    Text(isCached ? "\(modelKind.displayName) · Saved" : modelKind.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(intelligence.isOnDeviceModelAvailable ? "Apple Intelligence briefing" : "Offline briefing")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 4)

                        Divider()

                        if let availabilityMessage = intelligence.availability.message,
                           modelKind != .onDevice {
                            Label(availabilityMessage, systemImage: "info.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if isGenerating {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .controlSize(.regular)
                                Text("Downloading missing articles & synthesizing briefing…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        } else if !briefingText.isEmpty {
                            Text(briefingText)
                                .font(.system(size: 16, design: .serif))
                                .lineSpacing(6)
                                .textSelection(.enabled)
                        } else {
                            ContentUnavailableView(
                                "No Unread Articles",
                                systemImage: "tray.fill",
                                description: Text("You are all caught up! There are no unread stories to summarize.")
                            )
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: 620, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }

                if !briefingText.isEmpty && !isGenerating {
                    Divider()
                    HStack(spacing: 16) {
                        Button {
                            togglePlayback()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isPlayingBriefing ? (speaker.isPaused ? "play.fill" : "pause.fill") : "play.fill")
                                Text(isPlayingBriefing ? (speaker.isPaused ? "Resume" : "Pause") : "Listen")
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .frame(minWidth: 100)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.siftAccent)

                        Button {
                            Platform.copyToPasteboard(briefingText)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button {
                            Task {
                                await loadBriefing(forceRefresh: true)
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .help("Regenerate Briefing")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(.ultraThinMaterial)
                }
            }
            .navigationTitle("Sift Daily Briefing")
            #if os(macOS)
            .frame(minWidth: 520, minHeight: 440)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        if isPlayingBriefing {
                            speaker.stop()
                        }
                        dismiss()
                    }
                }
            }
            .task {
                await loadBriefing()
            }
            .onDisappear {
                if isPlayingBriefing {
                    speaker.stop()
                }
            }
        }
    }

    private func loadBriefing(forceRefresh: Bool = false) async {
        isGenerating = true
        let output = await intelligence.generateBriefingForUnreadArticles(
            context: modelContext,
            forceRefresh: forceRefresh
        )
        briefingText = output.text
        modelKind = output.modelKind
        isCached = output.isCached
        isGenerating = false
    }

    private func togglePlayback() {
        guard !briefingText.isEmpty else { return }
        speaker.speak(articleID: briefingID, title: "Sift Daily Briefing", text: briefingText)
    }
}
