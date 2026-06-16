import SwiftUI

/// Bottom bar: pick the folder to record into, then the one-button record /
/// stop control.
struct RecordBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var recorder: AudioRecorderService

    @State private var showNewFolder = false
    @State private var newFolderName = ""

    var body: some View {
        VStack(spacing: 12) {
            Divider()

            HStack {
                Text("Recording into")
                    .foregroundStyle(.secondary)

                Menu {
                    ForEach(model.folders) { folder in
                        Button {
                            model.selectFolder(folder.name)
                        } label: {
                            if folder.name == model.currentFolderName {
                                Label(folder.name, systemImage: "checkmark")
                            } else {
                                Text(folder.name)
                            }
                        }
                    }
                    Divider()
                    Button {
                        showNewFolder = true
                    } label: {
                        Label("New Folder…", systemImage: "folder.badge.plus")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(model.currentFolderName).fontWeight(.semibold)
                        Image(systemName: "chevron.up.chevron.down").font(.caption2)
                    }
                }
                .disabled(recorder.isRecording)

                Spacer()

                if recorder.isRecording {
                    Text(timeString(recorder.elapsed))
                        .monospacedDigit()
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal)

            Button {
                Task { await model.toggleRecording() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.red, lineWidth: 4)
                        .frame(width: 72, height: 72)
                    RoundedRectangle(cornerRadius: recorder.isRecording ? 6 : 32)
                        .fill(Color.red)
                        .frame(
                            width: recorder.isRecording ? 30 : 58,
                            height: recorder.isRecording ? 30 : 58
                        )
                        .animation(.easeInOut(duration: 0.2), value: recorder.isRecording)
                }
            }
            .accessibilityLabel(recorder.isRecording ? "Stop recording" : "Start recording")
            .padding(.bottom, 8)
        }
        .background(.bar)
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Create") {
                model.createFolder(newFolderName)
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) { newFolderName = "" }
        } message: {
            Text("Letters, digits, spaces, - and _ only.")
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
