import Foundation
import AVFoundation
import MediaPlayer
import Combine
import ActivityKit

/// Playback engine: an AVAudioEngine chain (player → 7-band EQ → mixer), so
/// the equalizer shapes the real output rather than sitting beside it.
/// Background audio, lock-screen / Control Center integration, Live Activity,
/// and per-track lyrics fetching (word timings win when a provider truly has
/// them).
@MainActor
final class PlayerService: ObservableObject {
    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isPlaying = false
    @Published var progress: Double = 0
    @Published private(set) var currentLyrics: [LyricsLine] = []
    @Published private(set) var lyricsLoading = false

    @Published var equalizer = Equalizer()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var sampleRate: Double = 44_100
    private var segmentOffsetSec: Double = 0
    private var segmentStartSample: AVAudioFramePosition = 0
    private var lastKnownProgress: Double = 0
    private var progressTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var lyricsTask: Task<Void, Never>?
    private var liveActivity: Activity<SonariqActivityAttributes>?
    private var lastActivityPush: (songId: UInt64, playing: Bool, at: Date)?

    var currentSong: Song? {
        guard let i = currentIndex, queue.indices.contains(i) else { return nil }
        return queue[i]
    }

    init() {
        engine.attach(playerNode)
        engine.attach(equalizer.unit)

        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }

        NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)
            .sink { [weak self] note in
                Task { @MainActor in self?.handleInterruption(note) }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .sink { [weak self] note in
                Task { @MainActor in self?.handleRouteChange(note) }
            }
            .store(in: &cancellables)

        // Forward equalizer changes so EQ-bound views refresh.
        equalizer.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        setupRemoteCommands()
    }

    // MARK: - Queue control

    func play(songs: [Song], startingAt index: Int) {
        guard songs.indices.contains(index) else { return }
        queue = songs
        playItem(at: index)
    }

    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    func resume() {
        guard currentSong != nil, !isPlaying else { return }
        if !engine.isRunning { try? engine.start() }
        playerNode.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        progress = currentPositionSec()
        lastKnownProgress = progress
        playerNode.pause()
        isPlaying = false
        updateNowPlayingInfo()
    }

    func next() {
        guard let i = currentIndex, !queue.isEmpty else { return }
        playItem(at: (i + 1) % queue.count)
    }

    func previous() {
        guard let i = currentIndex, !queue.isEmpty else { return }
        if progress > 3 { seek(to: 0); return }
        playItem(at: (i - 1 + queue.count) % queue.count)
    }

    func seek(to seconds: Double) {
        guard audioFile != nil else { return }
        let frame = AVAudioFramePosition(max(0, seconds) * sampleRate)
        scheduleSegment(fromFrame: frame, autoplay: isPlaying)
        progress = seconds
        lastKnownProgress = seconds
        updateNowPlayingInfo()
    }

    // MARK: - Queue editing

    /// Reorders the queue, keeping the current song's position correct.
    func move(from offsets: IndexSet, to destination: Int) {
        let currentId = currentSong?.id
        queue.move(fromOffsets: offsets, toOffset: destination)
        if let id = currentId {
            currentIndex = queue.firstIndex(where: { $0.id == id })
        }
    }

    /// Removes songs. Removing the playing song moves to whatever is now at
    /// its position; emptying the queue stops playback.
    func remove(at offsets: IndexSet) {
        let removedIds = Set(offsets.map { queue[$0].id })
        let currentId = currentSong?.id
        let removingCurrent = currentId.map { removedIds.contains($0) } ?? false
        queue.remove(atOffsets: offsets)
        if queue.isEmpty {
            stop()
            return
        }
        if removingCurrent {
            playItem(at: min(currentIndex ?? 0, queue.count - 1))
        } else if let id = currentId {
            currentIndex = queue.firstIndex(where: { $0.id == id })
        }
    }

    func clearQueue() {
        stop()
    }

    func stop() {
        playerNode.stop()
        lyricsTask?.cancel()
        queue = []
        currentIndex = nil
        isPlaying = false
        progress = 0
        lastKnownProgress = 0
        currentLyrics = []
        lyricsLoading = false
        updateNowPlayingInfo()
        endLiveActivity()
    }

    // MARK: - Engine

    private func playItem(at index: Int, skipCount: Int = 0) {
        guard queue.indices.contains(index), let url = queue[index].assetURL else { return }
        guard let file = try? AVAudioFile(forReading: url) else {
            // Unreadable (e.g. protected) — skip it rather than stalling the queue.
            guard skipCount < queue.count else { return }
            playItem(at: (index + 1) % queue.count, skipCount: skipCount + 1)
            return
        }
        currentIndex = index
        progress = 0
        lastKnownProgress = 0
        audioFile = file
        sampleRate = file.processingFormat.sampleRate
        do {
            engine.stop()
            playerNode.stop()
            engine.connect(playerNode, to: equalizer.unit, format: file.processingFormat)
            engine.connect(equalizer.unit, to: engine.mainMixerNode, format: file.processingFormat)
            try engine.start()
        } catch {
            print("Sonariq: engine start failed: \(error)")
            return
        }
        scheduleSegment(fromFrame: 0, autoplay: true)
        isPlaying = true
        updateNowPlayingInfo()
        loadLyrics(for: queue[index])
    }

    private func scheduleSegment(fromFrame frame: AVAudioFramePosition, autoplay: Bool) {
        guard let file = audioFile else { return }
        playerNode.stop()
        let remaining = file.length - frame
        guard remaining > 0 else { handleTrackEnd(); return }
        segmentOffsetSec = Double(frame) / sampleRate
        playerNode.scheduleSegment(file, startingFrame: frame,
                                   frameCount: AVAudioFrameCount(remaining), at: nil) { [weak self] in
            Task { @MainActor in self?.handleTrackEnd() }
        }
        if let nodeTime = playerNode.lastRenderTime,
           let pt = playerNode.playerTime(forNodeTime: nodeTime) {
            segmentStartSample = pt.sampleTime
        }
        if autoplay { playerNode.play() }
        progress = segmentOffsetSec
        lastKnownProgress = progress
    }

    private func handleTrackEnd() {
        next()
    }

    private func tick() {
        guard isPlaying else { return }
        progress = currentPositionSec()
        lastKnownProgress = progress
        updateNowPlayingInfo()
    }

    /// Sample-accurate position from the render clock; falls back to the last
    /// known value when the clock isn't available (e.g. right after a seek).
    private func currentPositionSec() -> Double {
        guard let nodeTime = playerNode.lastRenderTime,
              let playerTime = playerNode.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else { return lastKnownProgress }
        let elapsed = Double(playerTime.sampleTime - segmentStartSample) / playerTime.sampleRate
        return max(0, segmentOffsetSec + elapsed)
    }

    // MARK: - Lyrics

    private func loadLyrics(for song: Song) {
        lyricsTask?.cancel()
        currentLyrics = []
        lyricsLoading = true
        lyricsTask = Task {
            let result = await LyricsEngine.fetch(for: song)
            guard !Task.isCancelled else { return }
            currentLyrics = result?.lines ?? []
            lyricsLoading = false
        }
    }

    // MARK: - System integration

    private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            pause()
        case .ended:
            let options = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                resume()
            }
        @unknown default:
            break
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable else { return }
        pause() // Headphones unplugged.
    }

    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
    }

    // MARK: - Live Activity

    /// Pushes the now-playing Live Activity: on track change, play/pause, and
    /// at most every 5 seconds for progress (the system throttles harder).
    private func syncLiveActivity() {
        guard let song = currentSong else {
            endLiveActivity()
            return
        }
        let now = Date()
        let state = SonariqActivityAttributes.ContentState(
            title: song.title,
            artist: song.artist,
            isPlaying: isPlaying,
            progress: progress,
            duration: song.duration,
            artworkData: song.artwork?
                .image(at: CGSize(width: 160, height: 160))?.pngData()
        )
        if let activity = liveActivity {
            let last = lastActivityPush
            let changed = last?.songId != song.id || last?.playing != isPlaying
            let stale = last.map { now.timeIntervalSince($0.at) > 5 } ?? true
            guard changed || stale else { return }
            lastActivityPush = (song.id, isPlaying, now)
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let attributes = SonariqActivityAttributes(songId: song.id)
            if let activity = try? Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            ) {
                liveActivity = activity
                lastActivityPush = (song.id, isPlaying, now)
            }
        }
    }

    private func endLiveActivity() {
        guard let activity = liveActivity else { return }
        liveActivity = nil
        lastActivityPush = nil
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    private func updateNowPlayingInfo() {
        syncLiveActivity()
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: song.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: progress,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        if let artwork = song.artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
