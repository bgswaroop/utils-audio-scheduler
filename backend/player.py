import sounddevice as sd
import numpy as np
import miniaudio
import threading
import os

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

    def load_file(self, file_path: str):
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"Audio file not found: {file_path}")

        # Decode file using miniaudio (decodes MP3, WAV, FLAC, OGG, etc.)
        decoded = miniaudio.decode_file(file_path)
        samples = np.frombuffer(decoded.samples, dtype=np.float32)
        
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
                    
                    # Apply volume
                    weighted_chunk = chunk * self.volume
                    
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
            self.volume = max(0.0, min(1.0, val))

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
        self.player = AudioPlayer()
        self.player.on_track_end_callback = self._on_track_end
        self.current_playlist_id = None
        self.current_playlist_name = ""
        self.current_tracks = []
        self.current_track_index = -1
        self.device_id = None
        self.lock = threading.Lock()

    def set_device_id(self, device_id):
        with self.lock:
            # If changing device, we convert device_id to integer (or keep None)
            if device_id is not None:
                try:
                    self.device_id = int(device_id)
                except ValueError:
                    self.device_id = None
            else:
                self.device_id = None

    def play_playlist(self, playlist_id: int, playlist_name: str, tracks: list, start_index: int = 0):
        with self.lock:
            self.current_playlist_id = playlist_id
            self.current_playlist_name = playlist_name
            self.current_tracks = tracks
            self.current_track_index = start_index
            self._play_current_track_unlocked()

    def _play_current_track_unlocked(self):
        if not self.current_tracks or self.current_track_index < 0 or self.current_track_index >= len(self.current_tracks):
            self.player.stop_unlocked()
            self.current_playlist_id = None
            self.current_playlist_name = ""
            self.current_track_index = -1
            return

        track = self.current_tracks[self.current_track_index]
        file_path = track["file_path"]
        
        try:
            # First, release previous stream
            self.player.stop_unlocked()
            # Load and play
            self.player.load_file(file_path)
            self.player.play(device_id=self.device_id)
        except Exception as e:
            print(f"Playback error for track '{file_path}': {e}")
            # Skip to next track in separate thread to avoid nested locks
            threading.Thread(target=self.next_track, daemon=True).start()

    def _on_track_end(self):
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
            self.player.stop_unlocked()
            self.current_playlist_id = None
            self.current_playlist_name = ""
            self.current_tracks = []
            self.current_track_index = -1

    def pause(self):
        self.player.pause()

    def resume(self):
        self.player.resume()

    def set_volume(self, volume: float):
        self.player.set_volume(volume)

    def seek(self, progress: float):
        with self.lock:
            status = self.player.get_status()
            total_frames = status["total_frames"]
            if total_frames > 0:
                target_frame = int(progress * total_frames)
                self.player.set_position(target_frame)

    def get_status(self):
        with self.lock:
            status = self.player.get_status()
            current_track = None
            if self.current_tracks and 0 <= self.current_track_index < len(self.current_tracks):
                current_track = self.current_tracks[self.current_track_index]
            
            sr = status["samplerate"]
            current_time = status["current_frame"] / sr if sr > 0 else 0.0
            duration = status["total_frames"] / sr if sr > 0 else 0.0
            
            return {
                "playlist_id": self.current_playlist_id,
                "playlist_name": self.current_playlist_name,
                "current_track": current_track,
                "track_index": self.current_track_index,
                "total_tracks": len(self.current_tracks),
                "is_playing": status["is_playing"],
                "is_paused": status["is_paused"],
                "current_time": current_time,
                "duration": duration,
                "progress": status["progress"],
                "volume": status["volume"],
                "device_id": self.device_id
            }

# Singleton instance for the backend application
playback_manager = PlaybackManager()
