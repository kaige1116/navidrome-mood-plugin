To truly surpass existing solutions like AudioMuse-AI, there are a few enhancements you might consider:

Custom Subsonic Router Integration: Registering your analysis as a custom getSimilarSongs or getMoodPlaylists endpoint would allow third-party clients (like Symfonium or your own Android app) to tap into your sonic data natively.  

Dynamic "Mood Sliders": In the Web UI (via a sidecar page), allowing users to filter the library by "Energy 80%+, Sadness <20%" based on your Essentia tags would be a "killer feature" that even Spotify doesn't expose clearly.  

Automatic "Grouping" Injection: Using the plugin to write the analyzed Mood/BPM back into the Grouping or BPM fields of the Navidrome database so they are searchable in the standard UI.

**COMPLETE** | 12 May 2026 | Add some info about last time a playlist has been generated. Navidrome doesn't tell when was playlist last changed (also tested on Feishin, aonsoku, Symfonium and substreamer frontends). It could help with identifying non-working playlist generation (also, users may like that they know when it was laste generated).

An example how this is handled by a comment in https://github.com/kgarner7/navidrome-listenbrainz-daily-playlist  

It seems you've already solved the "hard" part (the signal analysis). Do you plan on integrating the results back into Navidrome's standard search filters, or keeping it strictly for playlist generation?

