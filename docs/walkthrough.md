# Walkthrough: Native macOS Audio Scheduler

We have built **utils-audio-scheduler**, a native macOS SwiftUI application with an embedded Python FastAPI background services manager, bundled into a standalone double-clickable `.app` bundle.

## Architecture Diagram

The architectural diagram below illustrates the components and interaction flow:

```mermaid
graph TD
    subgraph SwiftUI App Bundle ("utils-audio-scheduler.app")
        UI[SwiftUI Frontend Views]
        Client[BackendClient]
        Mgr[BackendManager Process Supervisor]
        SubProcess[Embedded Python Executable]
    end
    
    subgraph Local System Services
        DB[(SQLite File persistence)]
        CA[macOS CoreAudio Service]
        AudioOutput[Selected Output Routing]
    end

    UI -->|Triggers UI input| Client
    Client -->|Local REST HTTP Requests| SubProcess
    Mgr -->|Spawns & Supervises| SubProcess
    SubProcess -->|Query & Mutations| DB
    SubProcess -->|OutputStream Binds Device ID| CA
    CA -->|Direct Audio Routing| AudioOutput
```

## Key Technical Achievements

1. **Apple Music Visual Layout**: Implemented a modern native macOS design with a translucent sidebar, glassmorphic bottom floating player, detailed playlists grids, weekday scheduler checklists, and an audio settings panel.
2. **Channel-Normalized Audio Stream**: Built a custom Python audio streaming engine that decodes file formats using `miniaudio`, automatically duplicates mono files into stereo streams, and binds audio to user-selected CoreAudio output devices via `sounddevice` asynchronous callbacks, keeping standard system sound routing untouched.
3. **Application Process Supervision**: Programmed `App.swift` to automatically launch the compiled Python backend as a subprocess and cleanly terminate it on app closure. Added a watchdog monitoring daemon thread in the Python API that self-terminates if it gets re-parented (e.g. if the parent SwiftUI process crashes).
4. **Persistent Databases**: Kept database and settings configuration persistent in standard macOS path (`~/Library/Application Support/utils-audio-scheduler/audio_scheduler.db`).

## Execution and Test Verification

We verified the build pipeline by executing the `./build.sh` script, which:
- Formed the Python virtual environment and installed requirements.
- Compiled the backend Python script into a single binary (`backend`) via PyInstaller with device libraries collected.
- Compiled the SwiftUI code using the Swift compiler in release mode (`swift build -c release`).
- Configured a standard macOS `.app` bundle directory structure, copied compiled components, and wrote the launch metadata `Info.plist`.
- Formed a local Git repository and committed all code.

### Verification Commands

To check the `.app` bundle structure and ensure executables are in place, run:
```bash
ls -l utils-audio-scheduler.app/Contents/MacOS/utils-audio-scheduler
ls -l utils-audio-scheduler.app/Contents/Resources/backend
```

To run the standalone application, double-click the `.app` bundle from your Mac Finder, or launch it from terminal:
```bash
open utils-audio-scheduler.app
```

---

## Git Remote Setup and Push Instructions

The repository has been initialized and the code committed locally. To push the project to your remote GitHub repository, run the following exact commands in your terminal:

```bash
# 1. Navigate to the project root directory (if not already there)
cd /Users/guru/Documents/GitCode/utils-audio-scheduler

# 2. Push the committed main branch to GitHub
git push -u origin main
```
