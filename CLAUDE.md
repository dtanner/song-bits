# SongBits

iOS voice recorder for capturing song ideas. Recordings are organized
into folders; from a folder you can record straight into it.

Files are saved by default in the app's iCloud Drive container (shown as
"Song Bits" in iCloud Drive) so you can access them from other devices; the
app falls back to its local Documents while iCloud is unavailable.

## Build & run

The Xcode project is generated from `project.yml` by XcodeGen and is **not**
checked in. Use the justfile (`just` + `xcodegen` required):

Always edit `project.yml`, never the generated `.xcodeproj`. The default
simulator is `iPhone 17` (override with the `sim` variable in the justfile).

`just device` builds, installs, and launches on your iPhone (USB or Wi-Fi),
auto-discovering the first paired reachable one; pick a specific device with
`PHONE=<name-or-udid> just device`.

## Architecture

- **The filesystem is the database.** `RecordingStore` scans the configured root
  one level deep (folders, then `.m4a` files) and builds the catalog in memory;
  nothing about the catalog is persisted and all identity is path-based. Files
  moved in the Files app show up on next scan.
- **`AppModel`** (`@MainActor`, `ObservableObject`) is the single source of app
  state: the live catalog, the session's current folder, and the few persisted
  settings (root path, trim-silence, sort). It owns `AudioRecorderService` and
  `PlaybackService`.
- **Services** (`Services/`) hold the testable logic: `RecordingStore`,
  `AudioRecorderService`, `PlaybackService`, `OverdubService`, `AudioMixer`,
  `SilenceDetector`, `MicPermission`, and the `NameSanitizer` for
  recording/folder names.
- **Views** (`Views/`) are thin SwiftUI over `AppModel`. `RecordBar` takes an
  optional `fixedFolder`: at the root it shows the folder picker; inside a
  folder it records straight into that folder. The save-naming flow lives once
  on the root `NavigationStack` in `ContentView`, driven by
  `model.pendingRecording`.

## Conventions

- **Be concise.** Prefer the simplest design that is testable, debuggable, and
  conventional. Suggest a better approach when you see one — don't just
  implement the literal request.
- **Greenfield comments:** describe what the code *is* and why, never what it
  used to be or what changed. No "renamed from", no "previously".
- **Testing:** write tests for backend/service logic where practical, using
  **Swift Testing** (`@Test`/`#expect`) in the `SongBitsTests` target, run via
  `just test`. UI testing is done manually by the developer in the simulator;
  don't drive the app with UI-automation tools.
- **Docs:** README (user-facing features) and CONTRIBUTING (build/test/dev
  workflow) must stay accurate — update them in the same change that adds or
  renames a feature, recipe, or service. `Views/HelpView.swift` is the in-app
  help; keep it in step with user-visible behavior changes.
