# Bug Tracking

This document catalogs known issues, their root causes, and planned architectural fixes.

## Bug: Playlist Generation Timeout on Large Libraries (Resolved v0.5.9)

**Reported:** May 2026
**Environment:** Libraries > 15,000 tracks, specifically on lower-power CPUs (e.g., AMD R1505G).
**Symptom:** Playlist refresh fails silently or logs `error="plugin call failed: module closed"`.

### Root Cause Analysis
1. **Navidrome Scheduler Timeout:** Navidrome enforces a strict **30-second maximum execution time** for any function triggered by the scheduler.
2. **Sorting Overhead:** Sorting 86,000+ strings in every chunk task was exhausting the CPU budget.

### Fix (v0.5.7, v0.5.9)
- **Task Queue Offloading:** De-coupled generation from the scheduler.
- **Chunked Batching:** Library processed in batches of 2,000 tracks.
- **Sorted ID Caching:** The track index is sorted once at the start and cached in KV store to avoid redundant expensive sorts.

---

## Bug: Empty Playlists / Single-Track Playlists (Resolved v0.5.8)

**Reported:** May 2026
**Symptom:** Playlists were generated but were empty in the UI, and logs reported only "1 tracks" despite thousands of candidates.

### Root Cause Analysis
The `trackWithScores` struct used lowercase (private) field names (`id`, `name`, `artist`). In Go, private fields are ignored by the JSON serializer. When saving the temporary "best candidate" list to the KV store, all track metadata was erased, leaving a list of blank objects. The deduplication logic then merged these into a single "empty" track.

### Fix (v0.5.8)
Renamed struct fields to `ID`, `Name`, `Artist`, and `Scores` to make them public and serializable.

---

## Bug: Metadata Loss / Missing Song Names (Resolved v0.5.9)

**Reported:** May 2026
**Symptom:** Song names disappeared from the logs and index, replaced by blank strings.

### Root Cause Analysis
The `queueReanalysis` function (for uncertain tracks) failed to pass the existing Title/Artist in the task payload. When the re-analysis task finished, it updated the index with the blank metadata from the payload, overwriting the valid data.

### Fix (v0.5.9)
- **Metadata Persistence:** `queueReanalysis` now fetches and includes existing metadata in tasks.
- **Index Safeguard:** `updateIndex` will no longer overwrite an existing name with a blank string.

---

## Configuration Issue: Instant Mix Subsonic Agent Precedence (Resolved v0.5.5)

**Reported:** May 2026
**Symptom:** The Mood Playlists "Instant Mix" feature never triggers if other agents (e.g., AudioMuse-AI) take priority.

### Fix (v0.5.5)
Updated documentation in `README.md` and `HELP.md` explaining the `ND_AGENTS` environment variable requirement.