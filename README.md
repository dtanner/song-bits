# SongBits

An iOS voice recorder optimized for capturing song ideas. Tap record, hum or sing
the bit, name it (or don't), and it's saved. Recordings are organized into
regulars iCloud folders to make sharing and working across multiple devices easier.

## Highlights

- **One tap to record.** Big record button; stop, then optionally name the take
  before it's saved (defaults to a timestamp).
- **Folders.** Group takes by song or session. Record into a folder directly,
  move takes between folders, or archive ones you're done with.
- **The filesystem is the database.** Recordings are plain `.m4a` files on disk.
  Point the app at its own storage or a folder in iCloud Drive, and files you
  move in the Files app show up on the next scan.
- **Two play/pause buttons** while a take is expanded. The round button
  is a plain pause: it stops where you are and resumes from the
  same spot. The square play button is a DAW-style transport: pausing
  rewinds the playhead back to where playback last started, so you can audition
  the same bit over and over without scrubbing.
- **Search** across all recordings by file or folder name.
- **Skip leading silence** on playback (optional) so the quiet lead-in is
  skipped when you play.
- **Action Button / Shortcuts** support: "Open Recorder" foregrounds the app so
  you can tap record — it deliberately doesn't start recording hands-free.

## Screenshots

| Folders | Recordings | Settings |
| --- | --- | --- |
| <img src="https://github.com/dtanner/song-bits/releases/download/assets/01-root.png" width="240" alt="Folder list with record bar"> | <img src="https://github.com/dtanner/song-bits/releases/download/assets/02-folder.png" width="240" alt="Recording list with playback controls"> | <img src="https://github.com/dtanner/song-bits/releases/download/assets/03-settings.png" width="240" alt="Settings"> |

<sub>Images are hosted as assets on the [`assets` release](https://github.com/dtanner/song-bits/releases/tag/assets), not committed to the repo.</sub>

Requires iOS 17+.

## Contributing

Architecture, build & run, and testing notes live in
[CONTRIBUTING.md](CONTRIBUTING.md).
