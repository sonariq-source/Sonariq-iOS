import Foundation
import AVFoundation
import MediaPlayer
import Combine

/// Playback engine: AVPlayer queue, background audio, lock-screen / Control
/// Center integration via MPNowPlayingInfoCenter + remote commands.
@MainActor
final class PlayerService: ObservableObject {
    @Published private(set) var queue: [Song] = []
    @Published private(set) var currentIndex: Int?
    @Published private(set) var isPlaying = false
    @Published var progress: Double = 0

    @Published var equalizer = Equalizer()

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()

    var currentSong: Song? {
        guard let i = currentIndex, queue.indices.contains(i) else { return nil }
        return queue[i]
    }

    init() {
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.progress = time.seconds
                self?.updateNowPlayingInfo()
            }
        }

        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.next() }
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
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func pause() {
        player.pause()
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
        progress = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        updateNowPlayingInfo()
    }

    // MARK: - Private

    private func playItem(at index: Int) {
        guard queue.indices.contains(index),
              let url = queue[index].assetURL else { return }
        currentIndex = index
        progress = 0
        player.replaceCurrentItem(with: AVPlayerItem(url: url))
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
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

    private func updateNowPlayingInfo() {
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
