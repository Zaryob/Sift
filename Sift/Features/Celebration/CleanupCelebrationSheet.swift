import SwiftUI

/// An occasional, lightweight sheet celebrating how many promotional/sponsored
/// articles the SIFT Feed has kept out of the user's library since the last
/// time this was shown. Presented at most about once a week — see
/// `PromotionalCleanupStats`.
public struct CleanupCelebrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let count: Int

    public init(count: Int) {
        self.count = count
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.siftAccent, Color.purple.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    Image(systemName: "shield.checkered")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text("\(count)")
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.siftAccent)
                    .contentTransition(.numericText())

                Text("promotional & sponsored posts kept out of your SIFT Feed")
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Sift discards obvious ads and sponsored posts before they ever reach your library, so they don't take up space or your attention.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Text("Nice")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.siftAccent)
                .controlSize(.large)
            }
            .padding(28)
            .frame(maxWidth: 420)
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 420)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
