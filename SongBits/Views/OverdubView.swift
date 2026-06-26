import SwiftUI

/// The active overdub session: the backing take is already playing and the mic
/// is recording when this appears. Stop folds the two into a new take; cancel
/// discards the capture.
struct OverdubView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var overdub: OverdubService
    @Environment(\.dismiss) private var dismiss

    let backingName: String

    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Button("Cancel") {
                    model.cancelOverdub()
                    dismiss()
                }
                .disabled(model.isMixing)
                Spacer()
            }

            Spacer()

            VStack(spacing: 6) {
                Text("Overdubbing")
                    .font(.title2.weight(.semibold))
                Text("over “\(backingName)”")
                    .foregroundStyle(.secondary)
            }

            Label(routeMessage, systemImage: overdub.usingHeadphones ? "headphones" : "speaker.wave.2")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if model.isMixing {
                ProgressView("Mixing…")
                    .padding(.top, 8)
            } else {
                Text(timeString(overdub.elapsed))
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.red)
            }

            Spacer()

            Button {
                Task { await stopAndMix() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.red, lineWidth: 4)
                        .frame(width: 84, height: 84)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.red)
                        .frame(width: 34, height: 34)
                }
            }
            .accessibilityLabel("Stop overdub")
            .disabled(model.isMixing)
            .padding(.bottom, 32)
        }
        .padding()
        .presentationDragIndicator(.visible)
        // Force an explicit Stop or Cancel so the capture is always handled.
        .interactiveDismissDisabled(true)
    }

    /// Stops the take, mixes it down (spinner shows while mixing), then dismisses
    /// so the staged mix promotes into the naming flow on the way out.
    private func stopAndMix() async {
        await model.finishOverdub()
        dismiss()
    }

    private var routeMessage: String {
        overdub.usingHeadphones ? "Headphones — clean mix" : "Speaker — raw take"
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
