# Implementation Plan: Native macOS Audio Scheduler (SwiftUI + Python)

This plan outlines the architecture and implementation steps to build **utils-audio-scheduler**, a standalone macOS application consisting of a SwiftUI frontend that mimics Apple Music and a Python backend servicing audio storage, scheduling, and device-bound playback.

## User Review Required

> [!IMPORTANT]
> **Standalone Distribution Requirements**:
> To build a single standalone `.app` bundle, the Python backend will be compiled using `pyinstaller` into a single binary, which is then embedded inside the SwiftUI app bundle under `Contents/Resources` or `Contents/MacOS`. The SwiftUI app will start this binary as a background subprocess on a random or fixed local port.
>
> **CoreAudio Target Binding**:
> The Python audio player uses `sounddevice` to bind playback to the selected CoreAudio device ID, leaving the default system audio untouched. This requires local permission to access audio devices (microphone/output) in macOS, which the system will prompt for.

## Proposed Changes

We will create a unified folder structure:
* `utils-audio-scheduler/`
  * `backend/` - Python FastAPI REST API, SQLite database, audio player engine, scheduler.
  * `frontend/` - SwiftUI macOS application (managed via Swift Package Manager CLI to build as a native GUI bundle).
  * `build.sh` - Standard packaging script to compile Python backend, compile SwiftUI app, combine them into `utils-audio-scheduler.app`, and initialize git.

---

### Component: Python Backend (`backend/`)

The Python backend manages the database, parses audio files, plays audio on a specific device ID, and schedules playlists.

#### [NEW] [requirements.txt](file:///Users/guru/Documents/GitCode/utils-audio-scheduler/backend/requirements.txt)
Lists external Python dependencies:
- `fastapi` & `uvicorn[standard]` (REST API)
- `sounddevice` (Audio output binding)
- `miniaudio` (Clean MP3/WAV/FLAC decoders)
- `numpy` (Fast audio sample array manipulation)

#### [NEW] [db.py](file:///Users/guru/Documents/GitCode/utils-audio-scheduler/backend/db.py)
Manages the SQLite database schemas and queries.
- Tables:
  - `settings` (`key` TEXT PRIMARY KEY, `value` TEXT)
  - `playlists` (`id` INTEGER PRIMARY KEY, `name` TEXT)
  - `tracks` (`id` INTEGER PRIMARY KEY, `playlist_id` INTEGER, `file_path` TEXT, `title` TEXT, `duration` REAL, `track_order` INTEGER)
  - `schedules` (`id` INTEGER PRIMARY KEY, `playlist_id` INTEGER, `days_of_week` TEXT, `time_of_day` TEXT, `is_active` INTEGER)

#### [NEW] [player.py](file:///Users/guru/Documents/GitCode/utils-audio-scheduler/backend/player.py)
Implements device-bound audio playback.
- Decodes music using `miniaudio.decode_file` into a numpy float32 buffer (supports MP3, WAV, FLAC, OGG).
- Plays to a specific device index using `sounddevice.OutputStream` with a custom sample-feeding callback.
- Callback implementation allows real-time volume adjustment, track-skipping, pausing, stopping, and queryable current frame index/progress.
- Exposes `PlaybackManager` to queue and play tracks in a playlist sequentially.

#### [NEW] [scheduler.py](file:///Users/guru/Documents/GitCode/utils-audio-scheduler/backend/scheduler.py)
Implements a strict background scheduling loop.
- Runs as a daemon thread.
- Periodically checks the SQLite `schedules` table.
- Determines if the current system day of the week and local time matches a schedule's requirements.
- Automatically triggers immediate playlist playback on match, preventing multiple triggers within the same minute.

#### [NEW] [main.py](file:///Users/guru/Documents/GitCode/utils-audio-scheduler/backend/main.py)
Entrypoint for the FastAPI REST API.
- Exposes endpoints to control playback, manage playlists/schedules/tracks, scan and retrieve list of CoreAudio devices, and save selected settings.
- Binds to `127.0.0.1` on a port provided via CLI arguments.

---

### Component: SwiftUI Frontend (`frontend/`)

A standalone SwiftUI macOS application built using SPM, configured to run as a macOS graphical app.

#### [NEW] [Package.swift](file:///Users/guru/Documents/GitCode/utils-audio-scheduler/frontend/Package.swift)
Declares the executable target.

#### [NEW] [App.swift](file:///Users/guru/Documents/GitCode/utils-audio-scheduler/frontend/Sources/App.swift)
Sets the `@main` entry point. Configures the activation policy (`NSApp.setActivationPolicy(.regular)`) to display the UI properly, and spawns the Python backend subprocess on app startup, clean-killing it on exit.

#### [NEW] [BackendClient.swift](file:///Users/guru/Documents/GitCode/utils-audio-scheduler/frontend/Sources/BackendClient.swift)
Service client executing HTTP requests to the local Python REST API. Publishes status models to the SwiftUI views.

#### [NEW] [Views](file:///Users/guru/Documents/GitCode/utils-audio-scheduler/frontend/Sources/Views/)
- `MainView.swift`: Apple Music-inspired layout containing sidebar, details view, and bottom media player.
- `SidebarView.swift`: Sidebar for navigating between Playlists, Schedules, and Settings.
- `PlaylistsView.swift`: Grid/list of playlists, showing tracks list, a file selection sheet to add tracks (`NSOpenPanel`), and the "Test Now" button.
- `SchedulesView.swift`: Configuration view for scheduling playlist play times, with days of week selection, and a "Test Now" shortcut.
- `SettingsView.swift`: Dropdown picker querying available CoreAudio outputs from the backend, displaying service connection status.
- `MediaBarView.swift`: Persistent bottom playback controller with play/pause/stop buttons, volume slider, track title display, and a progress timeline bar.

---

### Component: Packaging & Tooling (`build.sh`)

#### [NEW] [build.sh](file:///Users/guru/Documents/GitCode/utils-audio-scheduler/build.sh)
Automates:
1. Virtual environment creation and Python library installation.
2. Compiling the Python backend using PyInstaller into a standalone executable.
3. Building the SwiftUI project using `swift build -c release`.
4. Packaging into a macOS `.app` bundle structure with `Info.plist`.
5. Embedding the Python binary inside the `.app` bundle structure.
6. Initializing Git, committing the code, and displaying instructions to push to the remote repo.

---

## Verification Plan

### Automated/Local Tests
- Python tests: Verify that `sounddevice` lists macOS core audio devices and loads files correctly.
- API tests: Query endpoints using `curl` to ensure endpoints return proper status and control playback.

### Manual Verification
1. Launch `utils-audio-scheduler.app` by double-clicking it.
2. Go to **Settings** and select an alternative output device (e.g., system output or virtual audio cable). Play a song and verify that it plays on that device ONLY, without shifting system sound defaults.
3. Create a Playlist, add files from `NSOpenPanel`, click "Test Now" and verify immediate playback.
4. Schedule a playlist for 1 minute in the future, wait, and verify it fires automatically on the schedule.
