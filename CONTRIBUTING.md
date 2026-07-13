# Contributing to SongBits

## Architecture

- **The filesystem is the database.** `RecordingStore` scans the configured
  root one level deep (folders, then `.m4a` files) and builds the catalog in
  memory. Nothing about the catalog is persisted; all identity is path-based.
- **`AppModel`** (`@MainActor`, `ObservableObject`) is the single source of app
  state: the live catalog, the session's current folder, and the few persisted
  settings (root folder bookmark, trim-silence, sort). It owns
  `AudioRecorderService` and `PlaybackService`.
- **Services** (`SongBits/Services/`) hold the testable logic: `RecordingStore`,
  `AudioRecorderService`, `PlaybackService`, `OverdubService`, `AudioMixer`,
  `SilenceDetector`, `MicPermission`, and the `RecordingName` / `FolderName`
  sanitizers.
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
| `just device` | Build, install, and launch on your iPhone (USB or Wi-Fi) |
| `just devices` | List connected devices and their UDIDs |
| `just shot <name>` | Screenshot the booted simulator into `marketing/screenshots/` |
| `just open` | Open the project in Xcode |
| `just clean` | Remove build artifacts |

Always edit `project.yml`, never the generated `.xcodeproj`. The default
simulator is `iPhone 17` (override with the `sim` variable in the justfile).

Device deploy (`just device`) needs a signing team — set `DEVELOPMENT_TEAM` in
`project.yml`. It auto-discovers the first paired reachable iPhone; target a
specific one with `PHONE=<name-or-udid> just device`.

## Testing

Service and backend logic is tested with [Swift Testing](https://developer.apple.com/documentation/testing)
(`@Test` / `#expect`) in the `SongBitsTests` target, run via `just test`. UI is
verified manually in the simulator.

## README image assets

README screenshots are hosted as assets on the
[`assets` release](https://github.com/dtanner/song-bits/releases/tag/assets)
rather than committed to the repo — they're kept out of git history and the
local `screenshots/` directory is gitignored. Each asset has a stable URL of the
form `https://github.com/dtanner/song-bits/releases/download/assets/<file>.png`,
which is what the README references.

Capture new screenshots from the simulator with:

```sh
xcrun simctl io booted screenshot screenshots/<file>.png
```

Then, using the [`gh`](https://cli.github.com) CLI:

```sh
# Refresh an existing asset (URL stays the same — no README change needed)
gh release upload assets screenshots/01-root.png --clobber

# Add a new asset
gh release upload assets screenshots/04-new.png

# Create the release the first time, if it doesn't exist yet
gh release create assets --title "README assets" \
    --notes "Image assets referenced from the README. Not part of git history." \
    screenshots/*.png
```

Reference a new asset in the README with its download URL.
