# Audio Tagging Roadmap: Permanent Metadata Injection

This document outlines the architectural plan and implementation steps for adding "Physical File Tagging" to the `navidrome-mood-plugin`. 

This feature will allow the Python analyzer service to permanently write AI-generated acoustic data (BPM and Mood Tags) directly into the physical audio files' metadata (ID3, Vorbis Comments, MP4 Atoms). This makes mood data natively searchable across all Subsonic clients and Navidrome's Web UI without requiring any custom frontend development.

## 1. Architectural Overview & The "Trojan Horse"

Because the Navidrome Go plugin operates in a restricted WASM sandbox and cannot efficiently parse or write to binary audio files, we leverage the existing Python `analyzer-service`.

**The Data Flow:**
1. User enables `Write Metadata to Audio Files` in the Navidrome plugin settings.
2. The Go plugin sends a `write_tags: true` flag in its analysis request payload to the Python service.
3. The Python service calculates the mood scores as usual.
4. Python uses the `mutagen` library to safely open the physical audio file (e.g., `.flac`, `.mp3`).
5. Python translates the float scores (e.g., `energy: 0.85`) into human-readable string tags (e.g., `#HighEnergy`).
6. Python safely appends these tags to the `Grouping` field and overwrites the `BPM` field.
7. Python saves the file. The file's `modified` timestamp updates on the host OS.
8. Navidrome's native `fsnotify` file watcher detects the change, automatically rescans the file, and seamlessly updates the UI database.

## 2. Phase 1: Go Plugin Configuration Updates

The feature must be strictly opt-in due to the nature of modifying user files.

### 2.1 Update `manifest.json`
- **Action:** Add a new configuration toggle under a "File Management" or "Advanced" group.
- **Key:** `write_metadata_to_files`
- **Title:** `Write Metadata to Audio Files`
- **Description:** `Append mood tags to the 'Grouping' field and update the 'BPM' field directly in your physical audio files. This makes moods searchable across all apps, but alters your files' modification dates and checksums.`
- **Default:** `false`

### 2.2 Update `main.go` Payload
- **Action:** Modify `onTaskExecute` to read the new `write_metadata_to_files` config.
- **Payload Change:** Update the JSON sent to `POST /api/analysis/file` (or `/url` if we mount the volume directly) to include the flag.
  ```json
  {
    "file_path": "/music/Artist/Album/Track.flac",
    "write_tags": true
  }
  ```
*(Note: File tagging requires the Python service to have direct file path access. If the current setup streams via URL, we must ensure the Python service has the absolute `file_path` and `rw` access to the mount).*

## 3. Phase 2: Python Analyzer Enhancements

The heavy lifting occurs in the FastAPI service using the `mutagen` library.

### 3.1 Dependencies
- **Action:** Add `mutagen==1.47.0` to `analyzer-service/requirements.txt`.

### 3.2 Tag Translation Logic
- **Action:** Create a helper function to convert float scores into searchable string tags.
- **Logic Matrix Example:**
  - `danceability >= 0.70` -> `#Danceable`
  - `energy >= 0.80` -> `#HighEnergy`
  - `energy <= 0.30` -> `#LowEnergy`
  - `mood_happy >= 0.60` -> `#Happy`
  - `mood_sad >= 0.50` -> `#Melancholy`
  - `mood_aggressive >= 0.60` -> `#Aggressive`
  - `mood_relaxed >= 0.60` -> `#Chill`

### 3.3 Safe Tagging Implementation (`mutagen`)
- **Action:** Implement a file-handler function that detects the file type and updates the metadata safely without corrupting the file or destroying existing user tags.
- **Requirements:**
  1. **Format Agnostic:** Must handle `.mp3` (ID3v2.3/2.4), `.flac` (Vorbis Comments), and `.m4a/.aac` (MP4 Atoms).
  2. **Safe Appending:** It must read the existing `Grouping` (or `CONTENTGROUP`) tag first. If it exists, append the new tags separated by a space (e.g., `Classical Movement 1 #Chill #LowEnergy`).
  3. **Deduplication:** Ensure we don't append `#Happy` multiple times if the file is re-analyzed.
  4. **BPM Update:** Write the rounded integer BPM (e.g., `124`) to the standard `TBPM` / `BPM` field.

## 4. Phase 3: Infrastructure & Documentation Requirements

Because this feature modifies files, the deployment infrastructure needs a slight tweak.

### 4.1 Docker Volume Permissions
- **Action:** Update `README.md` and setup instructions.
- **Change:** Users who want to use this feature must change their Docker volume mount from Read-Only (`:ro`) to Read-Write (`:rw` or simply omitted).
  - *Old:* `-v /path/to/your/music:/music:ro`
  - *New:* `-v /path/to/your/music:/music:rw`

### 4.2 Error Handling & Permissions
- **Action:** The Python script must catch `PermissionError`. If the user enabled the toggle but left the volume as `:ro`, the service must log a clear error warning ("Cannot write tags: Music directory is read-only") but still return the analysis scores to Navidrome so the pipeline doesn't break.

## 5. Implementation Milestones

1. **Python Dependency & Logic:** Add `mutagen`, write the Tag Translation dictionary, and implement the format-agnostic safe-append functions.
2. **API Contract:** Update the FastAPI endpoint to accept the `write_tags` boolean and trigger the mutagen logic after successful Essentia analysis.
3. **Go Plugin Update:** Add the UI toggle to `manifest.json` and pass the boolean in the HTTP request payload.
4. **Documentation:** Update README/HELP with the Docker `:rw` mount instructions and explain how users can now use the search bar to find `#HighEnergy` tracks.