import SwiftUI

/// Bottom bar: pick the folder to record into, then the one-button record /
/// stop control.
struct RecordBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var recorder: AudioRecorderService

    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var showNameRecording = false
    @State private var recordingName = ""
    @State private var defaultRecordingName = ""

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
        .onChange(of: model.pendingRecording) { _, pending in
            guard let pending else { return }
            // Leave the field empty so the user can just start typing; the
            // default name shows as a placeholder and is used on an empty save.
            recordingName = ""
            defaultRecordingName = pending.defaultName
            showNameRecording = true
        }
        .alert("Save Recording", isPresented: $showNameRecording) {
            TextField("Recording name", text: $recordingName, prompt: Text(defaultRecordingName))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") {
                model.savePendingRecording(named: recordingName)
            }
            Button("Delete", role: .cancel) {
                model.deletePendingRecording()
            }
        } message: {
            Text("Name this recording. Letters, digits, spaces, - and _ only.")
        }
    }

    private func timeString(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
