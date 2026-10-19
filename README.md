# Sonariq for iOS

Sonariq for iPhone — a native iOS music player built with Swift and SwiftUI.

> **Status: building.** The native Swift/SwiftUI app is in place and CI builds
> it on every push (macOS runner, unsigned simulator build + unsigned IPA for
> sideloading). Working now: Home (stats, albums, playlists), library
> browsing, queue with reorder/remove, AVAudioEngine playback (player →
> 7-band EQ → mixer, so the EQ shapes the real output) with background audio,
> lock-screen controls and a Live Activity (lock screen + Dynamic Island),
> and a real lyrics engine: lrc.red (true Apple word timings) and LRCLIB raced
> in parallel with a 12s timeout, word timings winning, disk cache, and
> word-level highlighting that appears only when the provider truly timed the
> words. Liquid Glass UI on iOS 26+, frosted material below. Still to come:
> streaming sources, Listen Together, CarPlay.

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
