import SwiftUI

/// In-app guide to the features that aren't obvious from the UI alone:
/// the two play/pause buttons, overdub's route-dependent behavior, and the
/// files-on-disk storage model.
struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Recording") {
                    helpRow(
                        "Capture a bit",
                        "Tap the red button to start, tap again to stop. On the main screen, pick the destination folder above the button; inside a folder, bits record straight into it."
                    )
                    helpRow(
                        "Naming",
                        "When you stop, the bit is already saved under a timestamp. Type a name and Save to rename it, or Cancel to keep the timestamp."
                    )
                }

                Section("Playback") {
                    helpRow(
                        "Expand a bit",
                        "Tap a recording's title to reveal the scrubber and transport controls without starting playback. The round play button plays immediately."
                    )
                    helpRow(
                        "Two play/pause buttons",
                        "The round button is a plain pause: it stops where you are and resumes from the same spot. The square button is a DAW-style transport: pausing rewinds to where playback last started, so you can audition the same bit over and over."
                    )
                    helpRow(
                        "Skip leading silence",
                        "Turn this on in Settings to jump past the quiet lead-in when playing. Files are never modified."
                    )
                }

                Section("Overdub") {
                    helpRow(
                        "Record over a bit",
                        "Expand a bit and tap the mic-with-music button. The bit plays while you record a new part, and the two are saved together as a new bit — the original is untouched."
                    )
                    helpRow(
                        "Headphones vs. speaker",
                        "Through headphones, the mic captures only your new part, so the app mixes the two evenly. On the speaker, the original is already coming through the mic, so the raw capture is kept as-is."
                    )
                    helpRow(
                        "Length",
                        "The part you record sets the length: run past the end of the original or stop short."
                    )
                }

                Section("Folders, Notes & Archive") {
                    helpRow(
                        "Organize",
                        "Use the … menu on a bit to rename it, move it to another folder, archive it, share it, or delete it."
                    )
                    helpRow(
                        "Folder notes",
                        "The note button inside a folder holds free-form text — lyrics, tunings, chord charts. Notes are saved as a plain notes.txt in the folder."
                    )
                    helpRow(
                        "Archive",
                        "Swipe a folder left to archive it. Archived folders move into an Archive folder on disk and disappear from the list; restore them from Settings."
                    )
                }

                Section("Files & iCloud") {
                    helpRow(
                        "Plain files",
                        "Recordings are ordinary .m4a files in named folders — no database. Anything you move or rename in the Files app shows up in Song Bits, and vice versa."
                    )
                    helpRow(
                        "Sync across devices",
                        "In Settings, choose a folder in iCloud Drive to keep recordings in sync and visible in Finder on your Mac. A cloud icon on a bit means it's still downloading — tap it to check again."
                    )
                }

                Section("Shortcuts") {
                    helpRow(
                        "Action Button",
                        "The “Open Recorder” shortcut brings Song Bits to the front ready to record — assign it to the Action Button for one-press access. It deliberately doesn't start recording hands-free."
                    )
                }
            }
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func helpRow(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
