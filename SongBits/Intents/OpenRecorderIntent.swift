import AppIntents

/// Foregrounds the app for the Action Button / Shortcuts. It deliberately does
/// NOT start recording — the user taps record in-app, which sidesteps the
/// hands-free "how do you stop?" problem.
struct OpenRecorderIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Recorder"
    static var description = IntentDescription("Opens SongBits so you can tap record.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        .result()
    }
}

struct SongBitsShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenRecorderIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Open Recorder in \(.applicationName)"
            ],
            shortTitle: "Open Recorder",
            systemImageName: "mic.circle"
        )
    }
}
