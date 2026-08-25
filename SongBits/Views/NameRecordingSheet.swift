import SwiftUI

/// Bottom sheet for naming a just-finished take. The take is already saved
/// under its default (timestamp) name, so every exit is safe: Save renames
/// (empty field keeps the default), swiping the sheet away keeps the default,
/// and Delete Take — kept small and well away from Save so it can't be hit
/// by habit — removes the file. The name field is not auto-focused: the
/// keyboard sliding in would shove the sheet upward just as the user reaches
/// for Save or Delete, so it appears only when they tap the field.
struct NameRecordingSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Name Recording")
                .font(.headline)
            TextField(model.pendingRecording?.defaultName ?? "", text: $name)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)
                .padding(10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 9))
            Text("Already saved under the default name.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: save) {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.top, 8)
            Button("Delete Take", role: .destructive) {
                model.deletePendingRecording()
                dismiss()
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
        .padding(20)
        .presentationDetents([.height(250)])
        .presentationDragIndicator(.visible)
        .onChange(of: name) { _, new in
            let filtered = NameSanitizer.filter(new)
            if filtered != new { name = filtered }
        }
    }

    private func save() {
        model.savePendingRecording(named: name)
        dismiss()
    }
}
