# Sonariq for iOS

Sonariq for iPhone — a native iOS music player built with Swift and SwiftUI.

> **Status: planning.** This is a fresh, native iOS build — not a port of the
> Android codebase. The v1.0 roadmap below is the starting scope.

## v1.0 roadmap (first iPhone release)

**Playback core**
- Local music library (MediaPlayer framework): songs, albums, artists, playlists
- Background audio + lock screen / Control Center controls (MPNowPlayingInfoCenter)
- Queue management: play next, reorder, shuffle, repeat

**Sonariq signature features**
- Synced lyrics view (line sync; word-sync where the provider supplies true timings)
- 7-band equalizer with presets
- Sleep timer
- Replay stats (weekly listening stats)

**Look & feel**
- Sonariq Prism design language (matte midnight/plum, coral primary, orchid secondary, cyan highlights)
- Light / dark mode

**Out of scope for v1.0** (come later): streaming sources, Listen Together,
CarPlay, widgets, offline downloads manager.

## Open source, kept secure

Like the Android project, this repo is open source — but secrets never live in
it:

- API keys and signing details go in `Secrets.xcconfig` (gitignored, never
  committed) — see `Secrets.xcconfig.example` for the shape.
- CI builds read the same values from GitHub Actions secrets.
- A fresh checkout with no secrets still compiles and runs; features that need
  a key simply stay disabled until one is provided.

## License

GPL-3.0 — like BitChord and ArchiveTune. See `LICENSE`.

---

by Sonariq studio
