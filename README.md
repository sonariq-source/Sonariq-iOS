# Sonariq for iOS

Sonariq for iPhone — a native iOS music player built with Swift and SwiftUI.

> **Status: foundation.** The native Swift/SwiftUI scaffold is in place and CI
> builds it on every push (macOS runner, unsigned simulator build). Working
> now: local library browsing, AVPlayer playback with background audio and
> lock-screen controls, queue, synced-lyrics view (LRC parser included;
> providers come next), 7-band EQ model with presets. Still to come: EQ engine
> wiring, streaming sources, Listen Together, CarPlay, widgets.

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
