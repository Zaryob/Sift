import SwiftUI
import SwiftData

struct AddFeedSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add RSS/Atom Feed")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Feed URL")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                TextField("https://example.com/feed.xml", text: $viewModel.addFeedURLString)
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.isAddingFeedLoading)
                    .onSubmit {
                        submit()
                    }
            }

            if viewModel.isAddingFeedLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching and validating feed...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    viewModel.isAddingFeed = false
                    dismiss()
                }
                .disabled(viewModel.isAddingFeedLoading)

                Button("Add Feed") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.addFeedURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isAddingFeedLoading)
            }
        }
        .padding()
        .frame(width: 420)
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
