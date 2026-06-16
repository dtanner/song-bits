# Voice Recorder (Folders-Only) — iOS App Build Plan

Handoff spec for a Claude Code session. The design is deliberately minimal:
**the filesystem IS the database.**

## Guiding principle

A recording belongs to exactly one folder, and that folder's name is its only
category. The folder tree under a configured root directory is the complete
source of truth. There is **no embedded metadata, no UUID, no tags, and no
persistent database** — the app reads the directory tree live and holds it in
memory.

This makes the saved data maximally portable (just `.m4a` files in named
folders, trivially readable on Android or anything else) and eliminates the
riskiest part of earlier designs — cross-platform metadata interop — entirely.

## Storage layout

```
<Documents>/<root>/
  unfiled/
    2026-06-15_14-30-00.m4a
    2026-06-15_15-02-11.m4a
  client-acme/
    2026-06-14_09-12-44.m4a
  ideas/
    ...
```

- `<root>` is configurable and lives under `Documents` (a relative path string).
- Immediate subfolders of `<root>` are the categories.
- Recordings are the `.m4a` files inside those subfolders.
- **One level only.** The app lists `<root>`'s subfolders and the files in each;
  it does NOT recurse deeper. Non-`.m4a` files are ignored.
- Default category for new recordings: `unfiled`, created under `<root>` if
  missing.

## Why no database / metadata / UUID

These existed in earlier designs only to keep a persistent cache in sync with
files that change underneath it. With folder-as-category:

- Identity = the file's current path. Self-updating, because the app re-reads the
  directory.
- A one-level directory listing is cheap, so the catalog is built live in memory
  on launch / foreground / after recording. No persistence needed for it.
- Moving a file between folders in Finder = recategorizing. Renaming a folder =
  renaming a category for all its files at once. Both are native filesystem
  operations the app picks up on its next read. No reconciliation logic.

There is NO per-directory file-count limit to worry about (APFS handles enormous
counts). Folders exist for human browsability, not a technical limit.

## What persists vs. what's in memory

Persisted (UserDefaults), tiny:
- root relative path under Documents
- trim-silence toggle

Derived from the filesystem on each read (in memory):
- **Recording:** url, filename, folder (parent dir name), createdAt (file date),
  duration (read lazily, optional)
- **Folder:** name, recordingCount, mostRecentDate (newest contained file's date,
  used for recent-first ordering)

Session only (reset on cold launch):
- **currentFolder** — defaults to `unfiled`; within a session, defaults to the
  last folder you recorded into.

## Two configuration settings (your question, resolved)

1. **Base/root directory** — configurable, a subfolder under Documents. A
   settings screen lets you pick or create it; stored as a relative path string.
   Persisted.
2. **Subdirectory handling** — RESOLVED as a fixed rule, not a toggle: one level
   (root -> category folders -> files), never recursive. This is the model, so it
   doesn't need to be a runtime setting.

## Features -> implementation

- **One-button recording:** `AVAudioRecorder`, M4A/AAC, write into currentFolder
  with a timestamp filename.
- **Shortcuts + Action Button:** App Intents "Open Recorder" intent that simply
  foregrounds the app. It does NOT start recording — the user taps record in-app.
  This sidesteps the hands-free "how do you stop?" problem entirely.
- **Keep recording through interruptions:** configure `AVAudioSession` so calls,
  other apps grabbing audio, screen lock, and app backgrounding do NOT stop the
  recording. Requires the `audio` background mode in Info.plist and interruption-
  handling that resumes rather than aborts.
- **Choose folder before or after:** pick a folder before recording (writes
  there), or record into the default and move the file to another folder
  afterward (a filesystem move).
- **Recent folders first:** sort folders by mostRecentDate (newest contained
  file) descending. Filesystem-derived; no stored recency.
- **Default folder `unfiled`:** cold-launch default; created if missing.
- **Session default to last folder:** in-memory currentFolder.
- **Folder-name validation:** folder names are real directory names, so allow
  only a safe character set (letters, digits, space, `-`, `_`); reject or
  sanitize everything else (`/`, leading dots, reserved names) for on-disk safety
  and cross-platform portability.
- **Browse in Finder:** `UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace`;
  the whole root tree is visible/editable in Finder (USB) and the Files app.
- **Share / export:** a share-sheet affordance on a recording (and optionally a
  folder) so files can be sent out of the app directly. Nearly free given the
  path-is-identity design; makes the portability tangible.
- **Configurable root:** settings screen (config #1).
- **Startup scan:** one-level directory read on launch + foreground + post-record.
- **Search by filename or folder:** substring match over the in-memory listing.
- **Skip leading silence on playback (global toggle):** files are never
  modified. On play, decode from the start until amplitude crosses a threshold,
  then set `currentTime` to that offset before `play()`. Compute per session
  (optionally hold offsets in an in-memory dict, recomputed on cold launch).
  (See concern 1.)

## Build phases

- **Phase 0 — Setup:** project, Info.plist (file sharing + open-in-place,
  `NSMicrophoneUsageDescription`, `audio` background mode), root-dir config +
  default `unfiled` creation.
- **Phase 1 — Record:** mic-permission flow; `AVAudioSession` configured to keep
  recording through interruptions / lock / backgrounding; one-button record ->
  `.m4a` into currentFolder, timestamp filename. Write to a temp name and move
  into the folder only on successful finalize (crash-safety).
- **Phase 2 — Browse:** one-level directory read; folder + recording list UI;
  live refresh on launch / foreground / post-record.
- **Phase 3 — Folder selection:** pick-before / move-after, recent-first
  ordering, session default, cold-start `unfiled`, folder-name validation.
- **Phase 4 — Search:** filename + folder substring search.
- **Phase 5 — Intents:** App Intents "Open Recorder" intent (foreground only) for
  Shortcuts + Action Button.
- **Phase 6 — Skip silence on playback:** global toggle; compute the first-sound
  offset and seek there before play. No file modification.
- **Phase 7 — Share / export:** share-sheet on a recording (and optionally a
  folder).
- **Phase 8 (optional) — In-app folder management:** create / rename / delete
  folders, move recordings between folders. Finder already does all this, so this
  is a convenience layer, not required.

## Concerns

1. **Skip is playback-only.** The leading silence stays in the file, so it still
   plays in Finder/QuickTime/other apps and on other platforms — the skip is
   purely this app's playback behavior. Get the threshold right (~−40 dBFS,
   require the signal to stay above it for a few ms so a click/pop doesn't
   trigger it) and handle the all-silent file by not skipping (start at 0).
2. **Filename collisions.** Timestamp to at least seconds; append a counter if
   rapid successive recordings could collide.
3. **Crash mid-recording.** A crash or force-quit can leave a truncated file.
   Write to a temp name and move into the folder only on successful finalize.
4. **File disappears underneath the app.** Reads are live, so a file deleted in
   Finder mid-session should fail gracefully on playback and drop off the next
   read. Minor.
5. **Loose files directly under root.** Decide whether to ignore `.m4a` files
   sitting in root (not in a category folder) or surface them. Recommendation:
   always record into a folder; ignore loose root files (or show them as
   `unfiled`).

## Eliminated vs. the earlier plan

Gone: UUID, embedded MP4 metadata atoms, the cross-platform metadata schema, the
SwiftData cache, the reconciliation algorithm, and the de-risking metadata
round-trip prototype. The portability goal is now satisfied by the folder
structure itself.
