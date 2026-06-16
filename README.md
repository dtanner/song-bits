# SongBits

A one-tap iOS voice recorder for capturing song ideas. Tap record, hum or sing
the bit, name it (or don't), and it's saved. Recordings are organized into
folders, and from inside a folder you can record straight into it.

## Highlights

- **One tap to record.** Big record button; stop, then optionally name the take
  before it's saved (defaults to a timestamp).
- **Folders.** Group takes by song or session. Record into a folder directly,
  move takes between folders, or archive ones you're done with.
- **The filesystem is the database.** Recordings are plain `.m4a` files on disk.
  Point the app at its own storage or a folder in iCloud Drive, and files you
  move in the Files app show up on the next scan.
- **Search** across all recordings by file or folder name.
- **Trim silence** on save (optional) so dead air at the ends gets cut.
- **Action Button / Shortcuts** support: "Open Recorder" foregrounds the app so
  you can tap record — it deliberately doesn't start recording hands-free.

## Architecture

- **The filesystem is the database.** `RecordingStore` scans the configured
  root one level deep (folders, then `.m4a` files) and builds the catalog in
  memory. Nothing about the catalog is persisted; all identity is path-based.
- **`AppModel`** (`@MainActor`, `ObservableObject`) is the single source of app
  state: the live catalog, the session's current folder, and the few persisted
  settings (root folder bookmark, trim-silence, sort). It owns
  `AudioRecorderService` and `PlaybackService`.
- **Services** (`SongBits/Services/`) hold the testable logic: `RecordingStore`,
  `AudioRecorderService`, `PlaybackService`, `SilenceDetector`, and the
  `RecordingName` / `FolderName` sanitizers.
- **Views** (`SongBits/Views/`) are thin SwiftUI over `AppModel`. `RecordBar`
  takes an optional `fixedFolder`: at the root it shows the folder picker;
  inside a folder it records straight into that folder. The save-naming flow
  lives once on the root `NavigationStack` in `ContentView`.

Storage defaults to the app's own `Documents/Recordings`. Pick another folder
(e.g. in iCloud Drive) and the app persists a security-scoped bookmark so
access survives relaunches.

Requires iOS 17+.

## Build & run

The Xcode project is generated from `project.yml` by
[XcodeGen](https://github.com/yonaskolb/XcodeGen) and is **not** checked in.
Build and run via the [`justfile`](justfile) (`just` + `xcodegen` required):

| Command | Does |
| --- | --- |
| `just` | List all recipes |
| `just generate` | Regenerate `SongBits.xcodeproj` from `project.yml` |
| `just build` | Build for the simulator |
| `just run` | Build, install, and launch in the simulator |
| `just logs` | Stream the app's logs from the booted simulator |
| `just test` | Run the test suite on the simulator |
| `just deploy` | Build, install, and launch on a connected iPhone |
| `just devices` | List connected devices and their UDIDs |
| `just open` | Open the project in Xcode |
| `just clean` | Remove build artifacts |

Always edit `project.yml`, never the generated `.xcodeproj`. The default
simulator is `iPhone 17` (override with the `sim` variable in the justfile).

Device deploy (`just deploy`) needs a signing team — set `DEVELOPMENT_TEAM` in
`project.yml`. Target a specific device with `DEVICE=<udid> just deploy`.

## Testing

Service and backend logic is tested with [Swift Testing](https://developer.apple.com/documentation/testing)
(`@Test` / `#expect`), run via `just test`. There is no test target yet — add a
`SongBitsTests` target in `project.yml` when introducing the first tests. UI is
verified manually in the simulator.
