import SwiftUI

@main
struct SongBitsApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(model.recorder)
                .environmentObject(model.playback)
                .onChange(of: scenePhase) { _, phase in
                    // Live refresh when the app comes to the foreground: the
                    // filesystem is the source of truth and may have changed
                    // (e.g. files moved in Finder / the Files app).
                    if phase == .active { model.refresh() }
                }
        }
    }
}
