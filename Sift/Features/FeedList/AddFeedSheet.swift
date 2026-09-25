import SwiftUI
import SwiftData

struct AddFeedSheet: View {
    @Bindable var viewModel: AppViewModel
    @Query private var feeds: [Feed]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    private var existingCategories: [String] {
        let cats = Set(feeds.compactMap { $0.category?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        return cats.sorted()
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [.orange, .red], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: "dot.radiowaves.up.and.right")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Add New Feed")
                        .font(.headline)
                    Text("Enter a website URL or direct RSS/Atom feed link.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 14) {
                // Feed URL
                VStack(alignment: .leading, spacing: 6) {
                    Label("Feed or Website URL", systemImage: "link")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("https://example.com/feed.xml", text: $viewModel.addFeedURLString)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isAddingFeedLoading)
                        .onSubmit {
                            submit()
                        }
                }

                // Folder / Category
                VStack(alignment: .leading, spacing: 6) {
                    Label("Folder / Category (Optional)", systemImage: "folder")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)

                    TextField("e.g. Technology, Design, News", text: $viewModel.addFeedCategoryString)
                        .textFieldStyle(.roundedBorder)
                        .disabled(viewModel.isAddingFeedLoading)
                        .onSubmit {
                            submit()
                        }

                    if !existingCategories.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(existingCategories, id: \.self) { cat in
                                    Button {
                                        viewModel.addFeedCategoryString = cat
                                    } label: {
                                        Text(cat)
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3)
                                            .background(
                                                Capsule()
                                                    .fill(viewModel.addFeedCategoryString == cat ? Color.accentColor : Color.secondary.opacity(0.12))
                                            )
                                            .foregroundStyle(viewModel.addFeedCategoryString == cat ? .white : .primary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }

            if viewModel.isAddingFeedLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching and validating feed...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            // Action Buttons
            HStack {
                Spacer()

                Button("Cancel") {
                    viewModel.isAddingFeed = false
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(viewModel.isAddingFeedLoading)

                Button("Subscribe") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.addFeedURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isAddingFeedLoading)
            }
        }
        .padding(22)
        #if os(macOS)
        .frame(width: 440)
        #else
        .frame(maxWidth: .infinity)
        .presentationDetents([.medium, .large])
        #endif
    }

    private func submit() {
        Task {
            await viewModel.addFeed(context: modelContext)
            if !viewModel.showErrorAlert {
                dismiss()
            }
        }
    }
}
