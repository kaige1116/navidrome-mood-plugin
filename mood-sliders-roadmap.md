# Technical Design Document: Dynamic Mood Sliders Integration

This document serves as the comprehensive technical roadmap for integrating real-time, client-side "Mood Sliders" into native Android (Phone/Tablet) and Windows Desktop Subsonic applications.

## 1. Architectural Overview & The Data Problem

The standard Subsonic API provides standard metadata (Title, Artist, Album, Duration, Genre). It **does not** support arbitrary custom fields like `Energy`, `Danceability`, or `Mood_Happy`.

Therefore, the client application cannot rely on Navidrome to filter tracks by mood. The client must:
1. Fetch the raw mood data from the `analyzer-service` directly.
2. Cache this data locally.
3. Perform the filtering against this local cache.
4. Match the filtered results to the standard Subsonic `Track IDs` it already knows about.

## 2. Phase 1: Backend Infrastructure Updates

To enable clients to fetch this data, the Python `analyzer-service` needs to become stateful.

### 2.1 Modifying the Go Plugin (`main.go`)
Currently, the Go plugin requests an analysis and stores the result in Navidrome's KVStore. The Python service forgets the data instantly.
*   **Change Required:** When the Go plugin calls `POST /api/analysis/url`, it must also pass the Navidrome `Track ID`.
*   **Payload Change:**
    ```json
    // New Request Payload
    {
      "track_id": "8a7b6c5d4e...",
      "url": "http://navidrome:4533/rest/stream?..."
    }
    ```

### 2.2 Updating the Python Analyzer Service (`app.py`)
The Python service must intercept this `track_id` and store the resulting scores in a local SQLite database before returning the response to the Go plugin.
*   **Database Schema (`mood_cache.db`):**
    ```sql
    CREATE TABLE track_scores (
        track_id TEXT PRIMARY KEY,
        mood_happy REAL,
        mood_sad REAL,
        mood_relaxed REAL,
        mood_aggressive REAL,
        mood_party REAL,
        danceability REAL,
        bpm REAL,
        energy REAL,
        arousal REAL,
        valence REAL,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
    );
    CREATE INDEX idx_updated_at ON track_scores(updated_at);
    ```

### 2.3 Creating the Client API Endpoint
The Python service must expose an endpoint for clients to bulk-download scores.
*   **Endpoint:** `GET /api/library/scores`
*   **Query Parameters:**
    *   `since` (optional): ISO 8601 timestamp. Returns only tracks analyzed or updated *after* this time (Incremental Sync). If omitted, returns the whole library (Full Sync).
*   **Headers Required:** `Accept-Encoding: gzip` (Critical for large libraries).
*   **Response Payload:**
    ```json
    {
      "server_time": "2026-05-12T19:30:00Z",
      "total_tracks": 15420,
      "scores": {
        "track_id_1": [0.85, 0.12, 0.05, 0.40, 0.90, 0.75, 124.0, 0.88], // Compressed array format to save bandwidth
        // Array mapping: [Happy, Sad, Relaxed, Aggressive, Party, Danceability, BPM, Energy]
      }
    }
    ```

### 2.4 Performance & Network Overhead
Mobile networks and storage are precious, so the sync engine is designed to be highly optimized.
*   **Payload Size:** A single Subsonic Track ID (32 bytes) + 8 mood scores compressed into an array (e.g., `[0.85,0.12,0.05,0.40,0.90,0.75,124.0,0.88]`) takes ~80 bytes. For a massive library of 50,000 tracks, the raw JSON is ~4MB.
*   **Compression:** With standard GZIP compression enabled on the endpoint, this payload shrinks by ~75% to **~1 Megabyte**. This is less data than a single high-res album cover.
*   **Sync Frequency:**
    *   **Initial Sync (Once):** Downloads the full ~1MB payload.
    *   **Incremental Sync (Daily/On Open):** Fetches only tracks analyzed since the `last_updated` timestamp. E.g., syncing 20 new tracks uses less than 2KB of data.

---

## 3. Phase 2: Client Implementation Foundations

Both the Android and Windows applications need a robust sync engine to maintain the local mood database.

### 3.1 App Settings UI
Add an **"AI Library Intelligence"** section in the app settings.
*   **Toggle:** `Enable Mood Filtering` (Default: Off). Explains that this requires the Navidrome Mood Plugin.
*   **Input:** `Analyzer Service URL` (e.g., `http://192.168.1.100:8000`).
*   **Action Button:** `Force Full Sync` (Shows last synced timestamp and total local mood tracks).

### 3.2 Client-Side Storage Schema
The client must mirror the Python database locally inside its secure sandbox (e.g., `/data/data/com.your.app/databases/moods.db`). It does *not* keep the raw JSON file.
*   **Why a local DB?** 
    1. **Zero Memory Bloat:** Loading 50,000 JSON records into RAM would cause crashes or lag. SQLite reads directly from disk instantly.
    2. **Instant Indexing:** Querying an indexed SQLite table for matching slider values returns results out of 50,000 tracks in <5 milliseconds.
*   **Android (Room Database):** Create a `@Entity` class `MoodScore`.
*   **Windows (SQLite via Entity Framework / Dapper):** Create a `MoodScore` model.
*   Both must index the `TrackId` as the Primary Key and create indexes on heavily queried columns like `Energy` and `BPM` to ensure 0-latency slider updates.

### 3.3 The Sync Engine (Background Worker)
*   **Initial Sync:** When the URL is saved, the app calls `GET /api/library/scores` (without `since`). It inserts all records into the local SQLite DB and saves the `server_time` to SharedPreferences/LocalSettings.
*   **Delta Sync:** Every time the app connects to the server (or daily in the background), it calls `GET /api/library/scores?since={saved_server_time}`. It UPSERTs the returned records and updates the saved timestamp.

---

## 4. Phase 3: Building the Native UI / UX

The filtering UI must feel like a native extension of the music library, not an afterthought.

### 4.1 Accessing the Feature
*   **Placement:** In the main "Songs" or "Tracks" view, alongside standard filters (Sort by Date, Filter by Genre), add a floating action button (FAB) featuring a "Sliders" or "Magic Wand" icon.
*   **Interaction:** Tapping this opens a Bottom Sheet (Android) or a Flyout Panel (Windows).

### 4.2 The Sliders Interface
The UI should group metrics logically to avoid overwhelming the user.

*   **Section 1: Vibe (Dual-thumb range sliders 0-100%)**
    *   `Energy` (Low -> High)
    *   `Happiness` (Sad -> Happy)
    *   `Chill` (Intense -> Relaxed)
*   **Section 2: Rhythm**
    *   `Danceability` (0-100%)
    *   `BPM Range` (Input fields or dual slider: Min `60` - Max `180`)
*   **Section 3: Actions**
    *   `Reset Filters` (Clears all)
    *   Real-time pill badge showing `[ 1,240 Tracks Match ]`.

### 4.3 The Filtering Algorithm (0-Latency Requirement)
When the user touches a slider, the library view behind the bottom sheet should update *instantly*.
*   **DO NOT** do this in memory using standard list filtering if the library > 10,000 tracks.
*   **DO** execute a localized SQLite query that joins the App's standard Subsonic Track table with the new `MoodScore` table.
*   **Example SQL (Android Room):**
    ```sql
    SELECT Tracks.* FROM Tracks
    INNER JOIN MoodScores ON Tracks.id = MoodScores.trackId
    WHERE MoodScores.energy >= :minEnergy
      AND MoodScores.energy <= :maxEnergy
      AND MoodScores.bpm >= :minBpm
      AND MoodScores.bpm <= :maxBpm
    ORDER BY Tracks.title ASC
    ```
*   Use Kotlin `Flow` (Android) or `IObservable` / Reactive extensions (Windows) to instantly emit the new list to the RecyclerView/DataGrid as the slider moves.

---

## 5. Phase 4: Playback & Subsonic API Integration

Once the user has filtered their view, they need to do something with those tracks.

### 5.1 Contextual Playback Actions
When the Mood Filter is active, the standard library buttons adapt:
*   **Shuffle All:** Now shuffles *only* the tracks currently matching the mood filter.
*   **Play Next:** Enqueues the filtered list.

### 5.2 "Save as Smart Mix" Button
Because the user spent time dialing in the perfect sliders, allow them to save it.
*   Add a `Save Mix` button to the UI.
*   When clicked, prompt for a name (e.g., "Late Night Coding").
*   The App takes the currently filtered list of `Track IDs` and executes a standard Subsonic API call:
    `GET /rest/createPlaylist?name=Late+Night+Coding&songId=id1&songId=id2...`
*   **Result:** The custom mix is permanently saved to the Navidrome server and synced across all their devices.

---

## 6. Implementation Milestones

1. **Backend Milestone:** Modify `main.go` to pass `track_id`. Modify Python service to implement SQLite storage and the `/api/library/scores` endpoint.
2. **Client Sync Milestone:** Implement the background incremental sync engine in the Android/Windows apps and verify the local database populates correctly.
3. **Client UI Milestone:** Build the slider UI components and wire them to emit filter states.
4. **Client DB Milestone:** Write the `JOIN` queries to merge the standard Subsonic track data with the new local mood data.
5. **Final Polish:** Implement the "Save Playlist" functionality and ensure UI responsiveness during active slider dragging.