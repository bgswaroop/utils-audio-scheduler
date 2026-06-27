import time
import datetime
import threading
import db
from player import playback_manager

class AudioScheduler:
    def __init__(self):
        self.running = False
        self.thread = None
        self.fired_cache = set()  # Stores tuples of (schedule_id, date_str, time_str)

    def start(self):
        if not self.running:
            self.running = True
            self.thread = threading.Thread(target=self._run_loop, daemon=True)
            self.thread.start()
            print("Scheduling engine started.")

    def stop(self):
        self.running = False
        if self.thread:
            self.thread.join(timeout=1.0)
            print("Scheduling engine stopped.")

    def _run_loop(self):
        while self.running:
            try:
                self._check_and_trigger()
            except Exception as e:
                print(f"Error in scheduler check: {e}")
            time.sleep(5)  # Poll every 5 seconds

    def _check_and_trigger(self):
        now = datetime.datetime.now()
        current_day = str(now.weekday())  # 0 = Monday, 6 = Sunday
        current_time_str = now.strftime("%H:%M")
        current_date_str = now.strftime("%Y-%m-%d")

        # Clean cache of dates older than today to save memory
        self.fired_cache = {item for item in self.fired_cache if item[1] == current_date_str}

        # Query all active schedules
        schedules = db.get_schedules()
        
        for sched in schedules:
            if not sched.get("is_active"):
                continue

            schedule_id = sched["id"]
            days_str = sched["days_of_week"]
            time_of_day = sched["time_of_day"]
            playlist_id = sched["playlist_id"]
            playlist_name = sched["playlist_name"]

            # Parse days of the week (comma separated integers)
            days = [d.strip() for d in days_str.split(",") if d.strip()]
            
            # Check if current day matches and current time matches HH:MM
            if current_day in days and time_of_day == current_time_str:
                cache_key = (schedule_id, current_date_str, current_time_str)
                if cache_key not in self.fired_cache:
                    # Trigger this playlist!
                    print(f"Triggering scheduled playlist '{playlist_name}' (ID: {playlist_id}) at {current_time_str}")
                    
                    tracks = db.get_tracks(playlist_id)
                    if tracks:
                        playback_manager.play_playlist(playlist_id, playlist_name, tracks)
                    else:
                        print(f"Warning: Scheduled playlist '{playlist_name}' is empty. Nothing to play.")
                    
                    self.fired_cache.add(cache_key)

scheduler = AudioScheduler()
