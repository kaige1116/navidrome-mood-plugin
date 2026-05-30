# Future Roadmap: Advanced Plugin Features

This document outlines the architectural plans and implementation steps for four major future enhancements to the `navidrome-mood-plugin`. These features transition the plugin from a library analysis utility into a highly personalized, reactive music discovery assistant.

---

## Feature 1: "Mood of the Day" Rotating Playlist

**Concept:** A single, dynamic playlist that changes its entire theme every 24 hours to solve the "paradox of choice" and encourage library exploration.

### Architectural Plan
This is the lowest-friction feature to implement as it leverages the existing playlist generation logic.

1. **Schedule Logic:**
   - Add a new cron schedule (e.g., `0 6 * * *` - 6 AM daily) specifically for the "Mood of the Day" task.
2. **Selection Algorithm:**
   - The plugin evaluates `time.Now().Weekday()`.
   - Map specific days to specific vibes to create a reliable rhythm (e.g., Monday = Workout/Energetic, Friday = Party, Sunday = Chill/Study).
   - *Alternative:* Implement a weighted randomizer so the user never knows what vibe they will get until they open the app.
3. **Playlist Generation:**
   - The plugin selects the 50 best tracks for the chosen mood.
   - It updates a dedicated Subsonic playlist explicitly named `Daily Vibe` or `Mood of the Day`.
4. **Metadata Updates:**
   - Update the description/comment of the playlist to explain the choice: *"Today's Vibe: High Energy Workout Mix. Generated at 6:00 AM."*
   - Update the playlist title (if the user has titles enabled) to reflect the day: `Daily Vibe (Monday: Energetic)`.

---

## Feature 2: Per-User Mood Playlists

**Concept:** Generating personalized mood mixes based on the specific listening habits and library access rights of individual users on a shared Navidrome server.

### Architectural Plan
Currently, playlists are generated globally under the admin account. This requires shifting to a user-centric loop.

1. **User Discovery:**
   - The plugin must query the Navidrome database/API to retrieve a list of all active users.
2. **Personalization Filtering (The Magic):**
   - For each user, the plugin fetches their "Starred/Favorited" tracks and "Top Played" tracks using the Subsonic API (e.g., `getStarred`, `getTopSongs`).
   - The plugin cross-references these user-specific IDs against the global `mood:index`.
   - Tracks that the user actively listens to receive an artificial "Score Boost" (e.g., +0.2 to their Happy score for that specific user's playlist).
3. **API Execution:**
   - The plugin iterates through the users.
   - It executes the `createPlaylist` / `updatePlaylist` Subsonic API calls *using that specific user's credentials or context*, ensuring the playlist is owned by them and only visible to them.

---

## Feature 3: Configurable Composite Thresholds

**Concept:** Allowing power users to easily tweak the complex mathematical rules behind composite playlists (e.g., changing "Study Mix" to allow slightly more Energy) without requiring coding knowledge.

### Architectural Plan
Requiring users to type JSON is bad UX. Instead, we lean into Navidrome's native `manifest.json` UI capabilities by creating collapsible configuration groups for the most popular composite playlists.

1. **UI Implementation (`manifest.json`):**
   - Add new `Group` elements to the `uiSchema` to visually box and organize these advanced settings, keeping the main settings page clean.
   - Example grouping: **"Advanced: Study Mix Tuning"**
     - Field: `study_max_energy` (Type: Number, Title: "Max Energy", Default: 0.15)
     - Field: `study_max_aggressive` (Type: Number, Title: "Max Aggression", Default: 0.20)
     - Field: `study_min_relaxed` (Type: Number, Title: "Min Relaxed Score", Default: 0.45)
2. **Go Parsing Logic (`main.go`):**
   - Currently, composite rules are hardcoded in the `compositeMoods` struct.
   - We will update the `refreshPlaylists` function to dynamically pull these values from `configFloat("study_max_energy", 0.15)`.
3. **UX Considerations:**
   - To avoid overwhelming the user, we don't need to expose *every* parameter for *every* playlist immediately. We can start by exposing the tuning dials for the top 3 most subjective playlists (e.g., Study, Workout, Sleep) where users are most likely to disagree on the default thresholds.

---

## Feature 4: Last.fm Reactive Listening Integration

**Concept:** The "Holy Grail" feature. The plugin reads a user's recent Last.fm scrobbles, calculates the average mood of what they are currently listening to, and instantly generates a "Current Vibe" playlist that matches their real-world mood.

### Architectural Plan
This is the most technically complex feature, requiring external API polling and fuzzy matching.

1. **Authentication:**
   - Add fields in the plugin settings for `Last.fm Username` and `Last.fm API Key`.
2. **Polling Engine:**
   - Implement a rapid background task (e.g., every 30-60 minutes).
   - The plugin queries the Last.fm `user.getRecentTracks` API to fetch the last 10 tracks played by the user.
3. **Fuzzy Matching (The Hard Part):**
   - Last.fm returns plain text (e.g., `"The Beatles" - "Let It Be"`). 
   - The plugin must query the local Navidrome API (or its internal `mood:index`) to find the corresponding Subsonic `Track ID`.
   - String normalization (lowercasing, stripping "Remastered 2009" tags) is required to ensure high match rates.
4. **Mood Calculation & Generation:**
   - Once the Subsonic IDs are found, the plugin pulls their mood scores from the KVStore.
   - It calculates the average vector (e.g., "The user's last 10 tracks average an Energy of 0.85 and a Sadness of 0.90").
   - The plugin queries the rest of the library to find the 30 closest matching tracks using Euclidean distance (similar to Instant Mix).
   - It updates a dedicated `Current Vibe` playlist.