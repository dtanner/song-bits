# SongBits

An iOS voice recorder optimized for capturing song ideas. Tap record, hum or sing
your idea, name it (or don't), and it's saved. Recordings are organized into
regular iCloud folders to make sharing and working across multiple devices easier.

## Highlights

- **One tap to record.** Big record button; stop, then optionally name the bit
  before it's saved (defaults to the date and time, like "Jul 7 2.32 PM").
- **Folders.** Group bits by song or session. Record into a folder directly,
  move them between folders, or archive ones — or whole folders — you're done
  with. Archived items wait in an Archived row at the bottom of the list they
  came from, where you can play, restore, or delete them.
- **Folder notes.** Each folder can hold free-form notes — lyrics, tunings,
  chord charts — stored as a plain `notes.txt` in the folder, so they sync and
  edit anywhere the files do.
- **Overdub.** Record a new part while an existing bit plays — sing a melody
  over a guitar idea — and Song Bits saves the two as a new bit. Through
  headphones it captures a clean layer and mixes them evenly; on the speaker it
  keeps the raw capture, since the backing is already coming through the mic. The
  part you record sets the length, so you can run past the original or stop short.
- **The filesystem is the database.** Recordings are plain `.m4a` files on disk.
  By default they live in **iCloud Drive → Song Bits**, synced across devices
  and visible in Finder on your Mac; pick any other folder in Settings. Files
  you move in the Files app show up on the next scan.
- **Two play/pause buttons** while a bit is expanded. The round button
  is a plain pause: it stops where you are and resumes from the
  same spot. The square play button is a DAW-style transport: pausing
  rewinds the playhead back to where playback last started, so you can audition
  the same bit over and over without scrubbing.
- **Search** across all recordings by file or folder name.
- **Skip leading silence** on playback (optional) so the quiet lead-in is
  skipped when you play.
- **Action Button / Shortcuts** support: "Open Recorder" foregrounds the app so
  you can tap record — it deliberately doesn't start recording hands-free.
- **Built-in help.** The ? button on the main screen explains the less obvious
  parts (transport buttons, overdub routing, Files-app sync) right in the app.

## Screenshots

<img src="https://github.com/dtanner/song-bits/releases/download/assets/02-folder.png" width="240" alt="Recording list with a bit expanded, showing the playback and overdub controls">

<sub>Image is hosted as an asset on the [`assets` release](https://github.com/dtanner/song-bits/releases/tag/assets), not committed to the repo.</sub>

Requires iOS 17+.

## Contributing

Architecture, build & run, and testing notes live in
[CONTRIBUTING.md](CONTRIBUTING.md).
