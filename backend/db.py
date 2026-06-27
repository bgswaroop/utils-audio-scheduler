import sqlite3
import os

def get_db_path():
    app_support = os.path.expanduser("~/Library/Application Support/utils-audio-scheduler")
    os.makedirs(app_support, exist_ok=True)
    return os.path.join(app_support, "audio_scheduler.db")

def get_connection():
    db_path = get_db_path()
    conn = sqlite3.connect(db_path)
    # Enable foreign keys
    conn.execute("PRAGMA foreign_keys = ON;")
    # Return rows as dictionaries
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_connection()
    cursor = conn.cursor()
    
    # 1. Settings Table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT
    );
    """)
    
    # 2. Playlists Table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE NOT NULL
    );
    """)
    
    # 3. Tracks Table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS tracks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL,
        file_path TEXT NOT NULL,
        title TEXT NOT NULL,
        duration REAL NOT NULL,
        track_order INTEGER NOT NULL,
        FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
    );
    """)
    
    # 4. Schedules Table
    cursor.execute("""
    CREATE TABLE IF NOT EXISTS schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER NOT NULL,
        days_of_week TEXT NOT NULL, -- Comma-separated indices, e.g., "0,1,2,3,4" (0=Mon, 6=Sun)
        time_of_day TEXT NOT NULL,  -- Format "HH:MM"
        is_active INTEGER DEFAULT 1, -- 1 = active, 0 = inactive
        FOREIGN KEY(playlist_id) REFERENCES playlists(id) ON DELETE CASCADE
    );
    """)
    
    conn.commit()
    conn.close()

# --- Helper DB Operations ---

# Settings
def get_setting(key: str, default: str = None) -> str:
    conn = get_connection()
    row = conn.execute("SELECT value FROM settings WHERE key = ?;", (key,)).fetchone()
    conn.close()
    return row["value"] if row else default

def set_setting(key: str, value: str):
    conn = get_connection()
    conn.execute(
        "INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value=excluded.value;",
        (key, value)
    )
    conn.commit()
    conn.close()

# Playlists
def get_playlists():
    conn = get_connection()
    rows = conn.execute("SELECT * FROM playlists ORDER BY name;").fetchall()
    playlists = [dict(row) for row in rows]
    conn.close()
    return playlists

def get_playlist(playlist_id: int):
    conn = get_connection()
    row = conn.execute("SELECT * FROM playlists WHERE id = ?;", (playlist_id,)).fetchone()
    playlist = dict(row) if row else None
    conn.close()
    return playlist

def create_playlist(name: str) -> int:
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute("INSERT INTO playlists (name) VALUES (?);", (name,))
    playlist_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return playlist_id

def delete_playlist(playlist_id: int):
    conn = get_connection()
    conn.execute("DELETE FROM playlists WHERE id = ?;", (playlist_id,))
    conn.commit()
    conn.close()

def rename_playlist(playlist_id: int, name: str):
    conn = get_connection()
    conn.execute("UPDATE playlists SET name = ? WHERE id = ?;", (name, playlist_id))
    conn.commit()
    conn.close()

# Tracks
def get_tracks(playlist_id: int):
    conn = get_connection()
    rows = conn.execute(
        "SELECT * FROM tracks WHERE playlist_id = ? ORDER BY track_order;",
        (playlist_id,)
    ).fetchall()
    tracks = [dict(row) for row in rows]
    conn.close()
    return tracks

def add_track(playlist_id: int, file_path: str, title: str, duration: float) -> int:
    conn = get_connection()
    cursor = conn.cursor()
    # Find the next order index
    row = conn.execute("SELECT MAX(track_order) as max_order FROM tracks WHERE playlist_id = ?;", (playlist_id,)).fetchone()
    next_order = (row["max_order"] + 1) if (row and row["max_order"] is not None) else 0
    
    cursor.execute(
        "INSERT INTO tracks (playlist_id, file_path, title, duration, track_order) VALUES (?, ?, ?, ?, ?);",
        (playlist_id, file_path, title, duration, next_order)
    )
    track_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return track_id

def delete_track(track_id: int):
    conn = get_connection()
    # Get playlist_id to adjust remaining tracks' orders later
    row = conn.execute("SELECT playlist_id, track_order FROM tracks WHERE id = ?;", (track_id,)).fetchone()
    if row:
        playlist_id = row["playlist_id"]
        order = row["track_order"]
        conn.execute("DELETE FROM tracks WHERE id = ?;", (track_id,))
        # Shift down order of tracks that were after this one
        conn.execute(
            "UPDATE tracks SET track_order = track_order - 1 WHERE playlist_id = ? AND track_order > ?;",
            (playlist_id, order)
        )
        conn.commit()
    conn.close()

def reorder_tracks(playlist_id: int, track_ids_ordered: list[int]):
    conn = get_connection()
    cursor = conn.cursor()
    for index, track_id in enumerate(track_ids_ordered):
        cursor.execute(
            "UPDATE tracks SET track_order = ? WHERE id = ? AND playlist_id = ?;",
            (index, track_id, playlist_id)
        )
    conn.commit()
    conn.close()

# Schedules
def get_schedules():
    conn = get_connection()
    rows = conn.execute("""
        SELECT s.*, p.name as playlist_name 
        FROM schedules s 
        JOIN playlists p ON s.playlist_id = p.id
        ORDER BY s.time_of_day;
    """).fetchall()
    schedules = [dict(row) for row in rows]
    conn.close()
    return schedules

def create_schedule(playlist_id: int, days_of_week: str, time_of_day: str) -> int:
    conn = get_connection()
    cursor = conn.cursor()
    cursor.execute(
        "INSERT INTO schedules (playlist_id, days_of_week, time_of_day, is_active) VALUES (?, ?, ?, 1);",
        (playlist_id, days_of_week, time_of_day)
    )
    schedule_id = cursor.lastrowid
    conn.commit()
    conn.close()
    return schedule_id

def delete_schedule(schedule_id: int):
    conn = get_connection()
    conn.execute("DELETE FROM schedules WHERE id = ?;", (schedule_id,))
    conn.commit()
    conn.close()

def toggle_schedule(schedule_id: int, is_active: int):
    conn = get_connection()
    conn.execute("UPDATE schedules SET is_active = ? WHERE id = ?;", (is_active, schedule_id))
    conn.commit()
    conn.close()
