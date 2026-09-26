import SwiftUI
import SwiftData

struct AddFeedSheet: View {
    @Bindable var viewModel: AppViewModel
    @Query private var feeds: [Feed]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var inputURL: String = ""
    @State private var isLookingUp: Bool = false
    @State private var isSubscribing: Bool = false
    @State private var selectedPreview: FeedPreview?
    @State private var choices: [DiscoveredFeed] = []
    @State private var inlineErrorMessage: String?
    @State private var selectedFolder: String?
    @State private var clipboardCandidate: (url: URL, host: String)?
    @State private var lookupTask: Task<Void, Never>?

    @FocusState private var isFieldFocused: Bool

    private var existingFeedURLs: Set<String> {
        Set(feeds.map(\.url))
    }

    private var existingCategories: [String] {
        let cats = Set(feeds.compactMap { $0.category?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return cats.sorted()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Single input field
                    inputSection

                    // Clipboard suggestion chip
                    if let candidate = clipboardCandidate, inputURL.isEmpty {
                        clipboardSuggestionButton(candidate)
                    }

                    // Inline error message
                    if let inlineErrorMessage {
                        errorMessageView(inlineErrorMessage)
                    }

                    // Loading indicator
                    if isLookingUp && selectedPreview == nil && choices.isEmpty {
                        loadingView
                    }

                    // Discovered feeds picker (if multiple feeds found)
                    if !choices.isEmpty && selectedPreview == nil {
                        multipleChoicesView
                    }

                    // Feed preview card
                    if let preview = selectedPreview {
                        previewCard(preview)
                    }

                    Spacer(minLength: 12)
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
            }
            .navigationTitle("Add Feed")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.isAddingFeed = false
                        dismiss()
                    }
                    .disabled(isSubscribing)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        confirmSubscription()
                    }
                    .fontWeight(.semibold)
                    .disabled(selectedPreview == nil || isSubscribing)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 480, minHeight: 420)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        .onAppear {
            isFieldFocused = true
            checkForClipboardURL()
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            TextField("Website or feed URL", text: $inputURL)
                .focused($isFieldFocused)
                #if os(iOS)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled(true)
                .submitLabel(.search)
                .onSubmit {
                    triggerImmediateLookup()
                }
                .onChange(of: inputURL) { _, newValue in
                    handleInputChange(newValue)
                }

            if isLookingUp {
                ProgressView()
                    .controlSize(.small)
            } else if !inputURL.isEmpty {
                Button {
                    inputURL = ""
                    clearState()
                    checkForClipboardURL()
                    isFieldFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(inputBackground)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private func clipboardSuggestionButton(_ candidate: (url: URL, host: String)) -> some View {
        Button {
            inputURL = candidate.url.absoluteString
            clipboardCandidate = nil
            triggerImmediateLookup()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard")
                    .font(.caption)
                Text("Use \(candidate.host) from clipboard")
                    .font(.subheadline.weight(.medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.siftAccent.opacity(0.12))
            .foregroundStyle(Color.siftAccent)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func errorMessageView(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.red)
                .font(.subheadline)
                .padding(.top, 1)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(.horizontal, 4)
        .transition(.opacity)
    }

    private var loadingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Finding feed...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    // MARK: - Multiple Choices View

    private var multipleChoicesView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Multiple Feeds Available")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(choices.enumerated()), id: \.element.url) { index, choice in
                    Button {
                        selectDiscoveredChoice(choice)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "dot.radiowaves.up.and.right")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.siftAccent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.title)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)

                                Text(choice.url.absoluteString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < choices.count - 1 {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .transition(.opacity)
    }

    // MARK: - Preview Card

    private func previewCard(_ preview: FeedPreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Favicon + Title + Host + Description
            HStack(alignment: .top, spacing: 12) {
                feedFavicon(preview)

                VStack(alignment: .leading, spacing: 3) {
                    Text(preview.parsed.title)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(preview.host)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if let desc = preview.parsed.feedDescription?.trimmingCharacters(in: .whitespacesAndNewlines), !desc.isEmpty {
                        Text(HTMLSanitizer.stripTags(from: desc))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)
            }

            // Metadata row: Articles count + Last updated
            HStack(spacing: 6) {
                Image(systemName: "newspaper")
                    .font(.caption2)
                Text("\(preview.parsed.items.count) articles")
                    .font(.caption.weight(.medium))

                if let latest = preview.latestDate {
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "clock")
                        .font(.caption2)
                    Text("Updated \(latest.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                }
            }
            .foregroundStyle(.secondary)

            // Last 3 Articles
            if !preview.parsed.items.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Articles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(preview.parsed.items.prefix(3).enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Circle()
                                    .fill(Color.siftAccent)
                                    .frame(width: 5, height: 5)
                                    .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title.isEmpty ? "Untitled Article" : item.title)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)

                                    Text(item.publicationDate.formatted(.relative(presentation: .named)))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }

                            if index < min(preview.parsed.items.count, 3) - 1 {
                                Divider()
                                    .padding(.leading, 13)
                            }
                        }
                    }
                }
            }

            // Choice Switcher (if multiple choices were available)
            if choices.count > 1 {
                Divider()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPreview = nil
                    }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text("Choose a different feed (\(choices.count) available)")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.siftAccent)
                }
                .buttonStyle(.plain)
            }

            // Optional Folder Selection (shown if categories exist)
            if !existingCategories.isEmpty {
                Divider()

                HStack {
                    Label("Add to Folder", systemImage: "folder")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Menu {
                        Button("None") {
                            selectedFolder = nil
                        }
                        Divider()
                        ForEach(existingCategories, id: \.self) { cat in
                            Button(cat) {
                                selectedFolder = cat
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(selectedFolder ?? "None")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(selectedFolder == nil ? .secondary : .primary)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
        .padding(16)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func feedFavicon(_ preview: FeedPreview) -> some View {
        let faviconURL = FaviconFetcher.faviconURL(
            for: preview.parsed.siteURL,
            feedURLString: preview.url.absoluteString,
            iconURLString: preview.parsed.iconURL
        )

        return Group {
            if let faviconURL {
                AsyncImage(url: faviconURL) { phase in
                    if case .success(let image) = phase {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        faviconPlaceholder
                    }
                }
            } else {
                faviconPlaceholder
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var faviconPlaceholder: some View {
        ZStack {
            Color.siftAccent.opacity(0.12)
            Image(systemName: "dot.radiowaves.up.and.right")
                .font(.headline.weight(.bold))
                .foregroundStyle(Color.siftAccent)
        }
    }

    // MARK: - Actions & Logic

    private func handleInputChange(_ text: String) {
        inlineErrorMessage = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        lookupTask?.cancel()

        if trimmed.isEmpty {
            clearState()
            checkForClipboardURL()
            return
        }

        clipboardCandidate = nil

        // Trigger debounced lookup only if it looks like a candidate domain or URL
        if trimmed.contains(".") || trimmed.lowercased().hasPrefix("http") || trimmed.lowercased().hasPrefix("feed") {
            lookupTask = Task {
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                await performLookup(query: trimmed)
            }
        }
    }

    private func triggerImmediateLookup() {
        let trimmed = inputURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lookupTask?.cancel()
        lookupTask = Task {
            await performLookup(query: trimmed)
        }
    }

    private func performLookup(query: String) async {
        isLookingUp = true
        inlineErrorMessage = nil

        do {
            let result = try await viewModel.lookUpFeed(query, existingFeedURLs: existingFeedURLs)
            guard !Task.isCancelled else { return }

            withAnimation(.easeInOut(duration: 0.25)) {
                switch result {
                case .preview(let preview):
                    self.selectedPreview = preview
                    self.choices = []
                case .choices(let choices):
                    self.choices = choices
                    self.selectedPreview = nil
                }
                self.isLookingUp = false
            }
        } catch {
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                self.selectedPreview = nil
                self.choices = []
                self.inlineErrorMessage = error.localizedDescription
                self.isLookingUp = false
            }
        }
    }

    private func selectDiscoveredChoice(_ choice: DiscoveredFeed) {
        isLookingUp = true
        inlineErrorMessage = nil
        lookupTask?.cancel()
        lookupTask = Task {
            do {
                let preview = try await viewModel.loadPreview(for: choice.url, existingFeedURLs: existingFeedURLs)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    self.selectedPreview = preview
                    self.isLookingUp = false
                }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    self.inlineErrorMessage = error.localizedDescription
                    self.isLookingUp = false
                }
            }
        }
    }

    private func confirmSubscription() {
        guard let preview = selectedPreview else { return }
        isSubscribing = true
        do {
            try viewModel.subscribe(to: preview, folder: selectedFolder, context: modelContext)
            dismiss()
        } catch {
            inlineErrorMessage = error.localizedDescription
            isSubscribing = false
        }
    }

    private func clearState() {
        selectedPreview = nil
        choices = []
        inlineErrorMessage = nil
        isLookingUp = false
    }

    private func checkForClipboardURL() {
        if let candidate = Platform.pasteboardCandidateURL() {
            if inputURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                clipboardCandidate = candidate
            }
        }
    }

    // MARK: - Styling Helpers

    private var inputBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemFill)
        #else
        Color.secondary.opacity(0.12)
        #endif
    }

    private var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
