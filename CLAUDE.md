# SongBits

iOS voice recorder for capturing song ideas. Recordings are organized
into folders; from a folder you can record straight into it.

Files are saved in an iCloud directory so you can access them from other devices.

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
  `AudioRecorderService`, `PlaybackService`, `SilenceDetector`, and the
  `RecordingName`/`FolderName` sanitizers.
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
  **Swift Testing** (`@Test`/`#expect`). There is no test target yet — add a
  `SongBitsTests` target in `project.yml` when introducing the first tests. UI
  testing is done manually by the developer in the simulator; don't drive the
  app with UI-automation tools.
