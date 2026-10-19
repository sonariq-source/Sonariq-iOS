import Foundation

/// Downloads resolved streams to the caches directory and hands back local
/// file URLs. The player reads from disk, so the 7-band EQ shapes streamed
/// audio exactly like local files — and a cached track plays offline.
/// Downloads in flight are shared: the play path and the read-ahead never
/// fetch the same track twice.
actor TrackCache {
    static let shared = TrackCache()

    private var inFlight: [String: Task<URL, Error>] = [:]

    private var directory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sonariq-streams", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cachedURL(videoId: String, ext: String) -> URL {
        directory.appendingPathComponent("\(videoId).\(ext)")
    }

    /// Local file for a remote song, downloading it first when needed.
    func localFile(for song: Song) async throws -> URL {
        guard let videoId = song.videoId else { throw StreamError.badResponse }
        // Fast path: already on disk (any known container).
        for ext in ["m4a", "webm"] {
            let url = cachedURL(videoId: videoId, ext: ext)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        if let task = inFlight[videoId] { return try await task.value }
        let task = Task<URL, Error> { [videoId] in
            let stream = try await StreamResolver.shared.resolve(videoId: videoId)
            return try await self.download(stream: stream, videoId: videoId)
        }
        inFlight[videoId] = task
        do {
            let url = try await task.value
            inFlight[videoId] = nil
            return url
        } catch {
            inFlight[videoId] = nil
            throw error
        }
    }

    /// Best-effort read-ahead for the queue; never throws.
    func prefetch(_ song: Song) {
        guard song.videoId != nil else { return }
        Task {
            _ = try? await localFile(for: song)
        }
    }

    /// True when the track is already fully on disk.
    func isCached(_ song: Song) -> Bool {
        guard let videoId = song.videoId else { return false }
        return ["m4a", "webm"].contains {
            FileManager.default.fileExists(atPath: cachedURL(videoId: videoId, ext: $0).path)
        }
    }

    private func download(stream: ResolvedStream, videoId: String) async throws -> URL {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForResource = 300
        let session = URLSession(configuration: config)
        var req = URLRequest(url: stream.url)
        for (k, v) in stream.headers { req.setValue(v, forHTTPHeaderField: k) }
        let (temp, response) = try await session.download(for: req)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code) else {
            if [403, 404, 410].contains(code) { throw StreamError.refused }
            throw StreamError.unreachable
        }
        let dest = cachedURL(videoId: videoId, ext: stream.fileExtension)
        if FileManager.default.fileExists(atPath: dest.path) {
            try? FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: temp, to: dest)
        return dest
    }
}
