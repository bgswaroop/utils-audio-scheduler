import sounddevice as sd
import numpy as np
import miniaudio
import threading
import os
import json

class AudioPlayer:
    def __init__(self):
        self.stream = None
        self.data = None
        self.samplerate = 0
        self.channels = 2  # Default to stereo for maximum compatibility
        self.current_frame = 0
        self.is_playing = False
        self.is_paused = False
        self.volume = 1.0
        self.device_id = None
        self.lock = threading.Lock()
        self.on_track_end_callback = None

    def set_audio_data(self, data, samplerate, channels):
        with self.lock:
            self.data = data
            self.samplerate = samplerate
            self.channels = channels
            self.current_frame = 0
            self.is_paused = False

    def load_file(self, file_path: str):
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"Audio file not found: {file_path}")

        # Decode file using miniaudio (decodes MP3, WAV, FLAC, OGG, etc.)
        decoded = miniaudio.decode_file(file_path)
        samples = np.frombuffer(decoded.samples, dtype=np.int16).astype(np.float32) / 32768.0
        
        with self.lock:
            self.samplerate = decoded.sample_rate
            nchannels = decoded.nchannels
            
            # Normalize mono files to stereo to avoid hardware device failures
            if nchannels == 1:
                self.data = np.column_stack((samples, samples))
                self.channels = 2
            else:
                self.data = samples.reshape(-1, nchannels)
                self.channels = nchannels
            
            self.current_frame = 0
            self.is_paused = False

    def play(self, device_id=None):
        with self.lock:
            if self.data is None:
                return
            
            self.stop_unlocked()
            self.device_id = device_id
            self.is_playing = True
            self.is_paused = False
            
            def callback(outdata, frames, time_info, status):
                if status:
                    print(f"Sounddevice callback status: {status}")
                
                with self.lock:
                    if not self.is_playing:
                        outdata.fill(0)
                        return
                    
                    if self.is_paused:
                        outdata.fill(0)
                        return
                    
                    # Fetch next chunk of samples
                    chunk = self.data[self.current_frame:self.current_frame + frames]
                    self.current_frame += len(chunk)
                    
                    # Apply volume and soft clip to prevent digital overflow/distortion
                    weighted_chunk = np.clip(chunk * self.volume, -1.0, 1.0)
                    
                    if len(chunk) < frames:
                        # End of file reached
                        outdata[:len(chunk)] = weighted_chunk
                        outdata[len(chunk):].fill(0)
                        self.is_playing = False
                        
                        # Trigger track end callback in a background thread
                        if self.on_track_end_callback:
                            threading.Thread(target=self.on_track_end_callback, daemon=True).start()
                    else:
                        outdata[:] = weighted_chunk

            # Start streaming to PortAudio output device
            self.stream = sd.OutputStream(
                device=self.device_id,
                samplerate=self.samplerate,
                channels=self.channels,
                callback=callback
            )
            self.stream.start()

    def stop(self):
        with self.lock:
            self.stop_unlocked()

    def stop_unlocked(self):
        self.is_playing = False
        self.is_paused = False
        if self.stream is not None:
            try:
                self.stream.stop()
                self.stream.close()
            except Exception as e:
                print(f"Error stopping stream: {e}")
            self.stream = None

    def pause(self):
        with self.lock:
            if self.is_playing:
                self.is_paused = True

    def resume(self):
        with self.lock:
            if self.is_playing:
                self.is_paused = False

    def set_volume(self, val: float):
        with self.lock:
            # Allow up to 200% (2.0) volume to act as preamp boost for quiet/feeble speakers
            self.volume = max(0.0, min(2.0, val))

    def set_position(self, frame: int):
        with self.lock:
            if self.data is not None:
                self.current_frame = max(0, min(len(self.data), frame))

    def get_status(self):
        with self.lock:
            total_frames = len(self.data) if self.data is not None else 0
            progress = self.current_frame / total_frames if total_frames > 0 else 0.0
            return {
                "is_playing": self.is_playing and not self.is_paused,
                "is_paused": self.is_paused,
                "current_frame": self.current_frame,
                "total_frames": total_frames,
                "samplerate": self.samplerate,
                "volume": self.volume,
                "progress": progress
            }


class PlaybackManager:
    def __init__(self):
        self.current_playlist_id = None
        self.current_playlist_name = ""
        self.current_tracks = []
        self.current_track_index = -1
        
        # Maps device_id (int) -> volume (float). Default is -1 (system default) at 100% volume
        self.active_devices = {-1: 1.0}
        # Maps device_id (int) -> AudioPlayer instance
        self.players = {}
        
        # Loaded track cache
        self.current_track_data = None
        self.current_samplerate = 0
        self.current_channels = 2
        
        self.is_paused = False
        self.master_volume = 1.0 # App-wide general volume scaling
        self.lock = threading.Lock()
        
        self.load_settings()

    def load_settings(self):
        # We delay-import db to avoid circular references during init
        import db
        try:
            active_ids_str = db.get_setting("active_device_ids")
            if active_ids_str:
                active_ids = json.loads(active_ids_str)
                # Keep active ids, map them with default volume or existing volume
                self.active_devices = {int(i): 1.0 for i in active_ids}
            else:
                self.active_devices = {-1: 1.0}
        except Exception as e:
            print(f"Error loading active devices settings: {e}")
            self.active_devices = {-1: 1.0}

        try:
            volumes_str = db.get_setting("device_volumes")
            if volumes_str:
                volumes = json.loads(volumes_str)
                for k, v in volumes.items():
                    # update active devices volumes
                    dev_id = int(k)
                    if dev_id in self.active_devices:
                        self.active_devices[dev_id] = float(v)
        except Exception as e:
            print(f"Error loading device volumes settings: {e}")

    def save_settings(self):
        import db
        try:
            active_ids = list(self.active_devices.keys())
            db.set_setting("active_device_ids", json.dumps(active_ids))
            db.set_setting("device_volumes", json.dumps({str(k): v for k, v in self.active_devices.items()}))
        except Exception as e:
            print(f"Error saving devices settings: {e}")

    def set_active_devices(self, device_ids: list[int]):
        with self.lock:
            # Determine which devices were added or removed
            old_device_ids = set(self.active_devices.keys())
            new_device_ids = set(device_ids)
            
            # Remove inactive players
            for dev_id in old_device_ids - new_device_ids:
                if dev_id in self.players:
                    self.players[dev_id].stop()
                    del self.players[dev_id]
                if dev_id in self.active_devices:
                    del self.active_devices[dev_id]
            
            # Add new players
            for dev_id in new_device_ids:
                if dev_id not in self.active_devices:
                    self.active_devices[dev_id] = 1.0 # Default volume 100%
                
                # If we are currently playing, dynamically spawn player for the new device
                if self.current_track_data is not None and dev_id not in self.players:
                    p = AudioPlayer()
                    p.on_track_end_callback = self._on_track_end
                    p.set_audio_data(self.current_track_data, self.current_samplerate, self.current_channels)
                    
                    # Sync frame position
                    master_frame = self._get_master_frame_unlocked()
                    p.set_position(master_frame)
                    
                    # Apply both master volume and device volume
                    p.set_volume(self.active_devices[dev_id] * self.master_volume)
                    
                    self.players[dev_id] = p
                    
                    # Start playback on this device
                    if any(player.is_playing for player in self.players.values() if player != p) or len(self.players) == 1:
                        p.play(device_id=None if dev_id == -1 else dev_id)
            
            self.save_settings()

    def set_device_volume(self, device_id: int, volume: float):
        with self.lock:
            # Allow up to 2.0 (200% boost) for quiet devices
            volume = max(0.0, min(2.0, volume))
            self.active_devices[device_id] = volume
            if device_id in self.players:
                self.players[device_id].set_volume(volume * self.master_volume)
            self.save_settings()

    def play_playlist(self, playlist_id: int, playlist_name: str, tracks: list, start_index: int = 0):
        with self.lock:
            self.current_playlist_id = playlist_id
            self.current_playlist_name = playlist_name
            self.current_tracks = tracks
            self.current_track_index = start_index
            self.is_paused = False
            self._play_current_track_unlocked()

    def _play_current_track_unlocked(self):
        # Stop all active players
        for p in self.players.values():
            p.stop_unlocked()
        
        if not self.current_tracks or self.current_track_index < 0 or self.current_track_index >= len(self.current_tracks):
            self.current_playlist_id = None
            self.current_playlist_name = ""
            self.current_track_index = -1
            self.current_track_data = None
            self.players.clear()
            return

        track = self.current_tracks[self.current_track_index]
        file_path = track["file_path"]
        
        try:
            if not os.path.exists(file_path):
                raise FileNotFoundError(f"Audio file not found: {file_path}")

            # 1. Decode current track once
            decoded = miniaudio.decode_file(file_path)
            samples = np.frombuffer(decoded.samples, dtype=np.int16).astype(np.float32) / 32768.0
            
            self.current_samplerate = decoded.sample_rate
            nchannels = decoded.nchannels
            
            if nchannels == 1:
                self.current_track_data = np.column_stack((samples, samples))
                self.current_channels = 2
            else:
                self.current_track_data = samples.reshape(-1, nchannels)
                self.current_channels = nchannels
            
            # 2. Assign audio data to players for all active devices
            self.players.clear()
            for dev_id, vol in self.active_devices.items():
                p = AudioPlayer()
                p.on_track_end_callback = self._on_track_end
                p.set_audio_data(self.current_track_data, self.current_samplerate, self.current_channels)
                p.set_volume(vol * self.master_volume)
                self.players[dev_id] = p
            
            # 3. Start playback on all players
            for dev_id, p in self.players.items():
                try:
                    p.play(device_id=None if dev_id == -1 else dev_id)
                except Exception as stream_err:
                    print(f"Error starting playback stream for device {dev_id}: {stream_err}")
                    
        except Exception as e:
            print(f"Playback error for track '{file_path}': {e}")
            # Skip to next track in separate thread to avoid nested locks
            threading.Thread(target=self.next_track, daemon=True).start()

    def _on_track_end(self):
        # Triggered when any of the players ends. We trigger next track
        self.next_track()

    def next_track(self):
        with self.lock:
            if self.current_playlist_id is None:
                return
            self.current_track_index += 1
            self._play_current_track_unlocked()

    def previous_track(self):
        with self.lock:
            if self.current_playlist_id is None:
                return
            self.current_track_index = max(0, self.current_track_index - 1)
            self._play_current_track_unlocked()

    def stop(self):
        with self.lock:
            for p in self.players.values():
                p.stop_unlocked()
            self.players.clear()
            self.current_playlist_id = None
            self.current_playlist_name = ""
            self.current_tracks = []
            self.current_track_index = -1
            self.current_track_data = None

    def pause(self):
        with self.lock:
            self.is_paused = True
            for p in self.players.values():
                p.pause()

    def resume(self):
        with self.lock:
            self.is_paused = False
            for p in self.players.values():
                p.resume()

    def set_volume(self, volume: float):
        with self.lock:
            # General app master volume
            self.master_volume = max(0.0, min(1.0, volume))
            for dev_id, p in self.players.items():
                p.set_volume(self.active_devices.get(dev_id, 1.0) * self.master_volume)

    def seek(self, progress: float):
        with self.lock:
            if self.current_track_data is None:
                return
            total_frames = len(self.current_track_data)
            target_frame = int(progress * total_frames)
            for p in self.players.values():
                p.set_position(target_frame)

    def _get_master_frame_unlocked(self) -> int:
        for p in self.players.values():
            if p.is_playing:
                return p.current_frame
        return 0

    def get_status(self):
        with self.lock:
            # Query the status of the first active player
            is_playing = False
            is_paused = self.is_paused
            current_frame = 0
            total_frames = len(self.current_track_data) if self.current_track_data is not None else 0
            samplerate = self.current_samplerate if self.current_samplerate > 0 else 44100
            
            # Find an active player to get current frames
            for p in self.players.values():
                if p.is_playing:
                    is_playing = True
                    current_frame = p.current_frame
                    break
            else:
                # If no players are currently playing but we are loaded, check if any is paused
                for p in self.players.values():
                    current_frame = p.current_frame
                    break
            
            current_time = current_frame / samplerate if samplerate > 0 else 0.0
            duration = total_frames / samplerate if samplerate > 0 else 0.0
            progress = current_frame / total_frames if total_frames > 0 else 0.0
            
            current_track = None
            if self.current_tracks and 0 <= self.current_track_index < len(self.current_tracks):
                current_track = self.current_tracks[self.current_track_index]
            
            return {
                "playlist_id": self.current_playlist_id,
                "playlist_name": self.current_playlist_name,
                "current_track": current_track,
                "track_index": self.current_track_index,
                "total_tracks": len(self.current_tracks),
                "is_playing": is_playing,
                "is_paused": is_paused,
                "current_time": current_time,
                "duration": duration,
                "progress": progress,
                "volume": self.master_volume,
                "active_devices": self.active_devices # Returns dict of id -> volume
            }

# Singleton instance
playback_manager = PlaybackManager()
