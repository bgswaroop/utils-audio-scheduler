from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os
import argparse
import miniaudio
import sounddevice as sd

import db
from player import playback_manager
from scheduler import scheduler

app = FastAPI(title="macOS Audio Scheduler API")

# Enable CORS for local API access
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Models ---
class PlaylistCreate(BaseModel):
    name: str

class TrackAdd(BaseModel):
    file_path: str

class ReorderTracks(BaseModel):
    track_ids: list[int]

class ScheduleCreate(BaseModel):
    playlist_id: int
    days_of_week: str  # Comma separated indices e.g. "0,1,2,3,4"
    time_of_day: str   # Format "HH:MM"

class VolumeSet(BaseModel):
    volume: float

class DeviceSet(BaseModel):
    device_id: int

class SeekSet(BaseModel):
    progress: float

# --- Endpoints ---

# 1. Devices Settings
@app.get("/devices")
def list_devices():
    devices = []
    try:
        device_list = sd.query_devices()
        default_output = sd.default.device[1]
        for index, d in enumerate(device_list):
            if d["max_output_channels"] > 0:
                devices.append({
                    "id": index,
                    "name": d["name"],
                    "max_output_channels": d["max_output_channels"],
                    "is_default": index == default_output
                })
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to query audio devices: {e}")
    return devices

@app.get("/settings/device")
def get_selected_device():
    device_id = db.get_setting("selected_device_id")
    return {"device_id": int(device_id) if device_id is not None else None}

@app.post("/settings/device")
def set_selected_device(payload: DeviceSet):
    # Verify device exists
    try:
        devices = sd.query_devices()
        if payload.device_id < 0 or payload.device_id >= len(devices):
            raise HTTPException(status_code=400, detail="Invalid device ID")
    except Exception as e:
        if isinstance(e, HTTPException):
            raise e
        raise HTTPException(status_code=500, detail=f"Error checking device ID: {e}")
    
    db.set_setting("selected_device_id", str(payload.device_id))
    playback_manager.set_device_id(payload.device_id)
    return {"status": "ok", "device_id": payload.device_id}

# 2. Playlists
@app.get("/playlists")
def get_playlists():
    return db.get_playlists()

@app.post("/playlists")
def create_playlist(payload: PlaylistCreate):
    try:
        playlist_id = db.create_playlist(payload.name)
        return {"id": playlist_id, "name": payload.name}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Playlist creation failed: {e}")

@app.delete("/playlists/{playlist_id}")
def delete_playlist(playlist_id: int):
    # If the playlist is currently playing, stop it first
    status = playback_manager.get_status()
    if status["playlist_id"] == playlist_id:
        playback_manager.stop()
    db.delete_playlist(playlist_id)
    return {"status": "ok"}

# 3. Tracks
@app.get("/playlists/{playlist_id}/tracks")
def get_tracks(playlist_id: int):
    return db.get_tracks(playlist_id)

@app.post("/playlists/{playlist_id}/tracks")
def add_track(playlist_id: int, payload: TrackAdd):
    if not os.path.exists(payload.file_path):
        raise HTTPException(status_code=404, detail=f"Audio file not found: {payload.file_path}")
    
    try:
        info = miniaudio.get_file_info(payload.file_path)
        title = os.path.splitext(os.path.basename(payload.file_path))[0]
        track_id = db.add_track(playlist_id, payload.file_path, title, info.duration)
        return {"id": track_id, "title": title, "duration": info.duration}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to read audio file metadata: {e}")

@app.delete("/tracks/{track_id}")
def delete_track(track_id: int):
    # Check if deleting the track currently playing
    status = playback_manager.get_status()
    if status["current_track"] and status["current_track"]["id"] == track_id:
        playback_manager.next_track()
    db.delete_track(track_id)
    return {"status": "ok"}

@app.put("/playlists/{playlist_id}/tracks/order")
def reorder_tracks(playlist_id: int, payload: ReorderTracks):
    try:
        db.reorder_tracks(playlist_id, payload.track_ids)
        return {"status": "ok"}
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Reordering failed: {e}")

# 4. Schedules
@app.get("/schedules")
def get_schedules():
    return db.get_schedules()

@app.post("/schedules")
def create_schedule(payload: ScheduleCreate):
    # Validate playlist exists
    playlist = db.get_playlist(payload.playlist_id)
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")
    
    # Validate days_of_week and time_of_day format
    try:
        days = [int(d.strip()) for d in payload.days_of_week.split(",") if d.strip()]
        for d in days:
            if d < 0 or d > 6:
                raise ValueError("Days must be 0-6")
        
        # Verify HH:MM format
        parts = payload.time_of_day.split(":")
        if len(parts) != 2 or not (0 <= int(parts[0]) <= 23) or not (0 <= int(parts[1]) <= 59):
            raise ValueError("Time must be HH:MM")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid scheduling parameters: {e}")
    
    schedule_id = db.create_schedule(payload.playlist_id, payload.days_of_week, payload.time_of_day)
    return {"id": schedule_id, "playlist_id": payload.playlist_id, "days_of_week": payload.days_of_week, "time_of_day": payload.time_of_day}

@app.delete("/schedules/{schedule_id}")
def delete_schedule(schedule_id: int):
    db.delete_schedule(schedule_id)
    return {"status": "ok"}

@app.put("/schedules/{schedule_id}/toggle")
def toggle_schedule(schedule_id: int, is_active: bool):
    db.toggle_schedule(schedule_id, 1 if is_active else 0)
    return {"status": "ok", "is_active": is_active}

# 5. Playback Operations & "Test Now" Trigger
@app.post("/playlists/{playlist_id}/play")
def play_playlist(playlist_id: int):
    playlist = db.get_playlist(playlist_id)
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")
    
    tracks = db.get_tracks(playlist_id)
    if not tracks:
        raise HTTPException(status_code=400, detail="Playlist has no tracks")
    
    playback_manager.play_playlist(playlist_id, playlist["name"], tracks)
    return {"status": "started", "playlist": playlist["name"]}

@app.post("/schedules/{schedule_id}/test")
def test_schedule(schedule_id: int):
    conn = db.get_connection()
    sched = conn.execute("SELECT * FROM schedules WHERE id = ?;", (schedule_id,)).fetchone()
    conn.close()
    if not sched:
        raise HTTPException(status_code=404, detail="Schedule not found")
    
    playlist_id = sched["playlist_id"]
    playlist = db.get_playlist(playlist_id)
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")
        
    tracks = db.get_tracks(playlist_id)
    if not tracks:
        raise HTTPException(status_code=400, detail="Playlist has no tracks")
        
    playback_manager.play_playlist(playlist_id, playlist["name"], tracks)
    return {"status": "started", "playlist": playlist["name"]}

@app.get("/playback/status")
def get_playback_status():
    return playback_manager.get_status()

@app.post("/playback/stop")
def stop_playback():
    playback_manager.stop()
    return {"status": "stopped"}

@app.post("/playback/pause")
def pause_playback():
    playback_manager.pause()
    return {"status": "paused"}

@app.post("/playback/resume")
def resume_playback():
    playback_manager.resume()
    return {"status": "resumed"}

@app.post("/playback/next")
def next_playback():
    playback_manager.next_track()
    return {"status": "skipped_next"}

@app.post("/playback/previous")
def previous_playback():
    playback_manager.previous_track()
    return {"status": "skipped_previous"}

@app.post("/playback/volume")
def set_volume(payload: VolumeSet):
    playback_manager.set_volume(payload.volume)
    db.set_setting("volume", str(payload.volume))
    return {"status": "ok", "volume": payload.volume}

@app.post("/playback/seek")
def seek_playback(payload: SeekSet):
    playback_manager.seek(payload.progress)
    return {"status": "ok", "progress": payload.progress}

# --- Service Startup ---
if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="utils-audio-scheduler Python Backend")
    parser.add_argument("--host", type=str, default="127.0.0.1", help="API server bind host")
    parser.add_argument("--port", type=int, default=18088, help="API server port")
    args = parser.parse_args()

    # 1. Initialize DB tables
    db.init_db()

    # 2. Restore user configurations from DB
    saved_device = db.get_setting("selected_device_id")
    if saved_device is not None:
        try:
            playback_manager.set_device_id(int(saved_device))
        except ValueError:
            pass

    saved_volume = db.get_setting("volume")
    if saved_volume is not None:
        try:
            playback_manager.set_volume(float(saved_volume))
        except ValueError:
            pass

    # 3. Start Scheduling Polling Thread
    scheduler.start()

    # Monitor parent process (SwiftUI App) so we self-terminate if parent dies
    import threading
    def watch_parent():
        import os
        import time
        while True:
            # If parent PID is 1, it means the parent process died and we were re-parented to launchd
            if os.getppid() == 1:
                print("Parent process exited. Terminating backend daemon.")
                os._exit(0)
            time.sleep(2)
    
    watcher_thread = threading.Thread(target=watch_parent, daemon=True)
    watcher_thread.start()

    # 4. Start FastAPI server via Uvicorn
    import uvicorn
    uvicorn.run(app, host=args.host, port=args.port)
