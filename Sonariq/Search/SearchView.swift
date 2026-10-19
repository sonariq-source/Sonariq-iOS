import SwiftUI

/// Search the music service — songs, albums, artists, playlists — and play
/// anything straight from the results.
struct SearchView: View {
    @EnvironmentObject var player: PlayerService
    @State private var query = ""
    @State private var filter: SearchFilter = .all
    @State private var results: SearchResults?
    @State private var searching = false
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    filterChips
                    Group {
                        if searching && results == nil {
                            Spacer()
                            ProgressView().tint(Theme.coral)
                            Spacer()
                        } else if let error {
                            Spacer()
                            Text(error)
                                .foregroundColor(Theme.textDim)
                                .multilineTextAlignment(.center)
                                .padding()
                            Spacer()
                        } else if let results {
                            resultsList(results)
                        } else {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundColor(Theme.coral)
                                Text("Search millions of songs")
                                    .foregroundColor(Theme.textDim)
                            }
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Songs, albums, artists")
            .onSubmit(of: .search) { runSearch() }
            .onChange(of: filter) { _, _ in runSearch() }
        }
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchFilter.allCases) { f in
                    Button {
                        filter = f
                    } label: {
                        Text(f.label)
                            .font(.subheadline).bold(filter == f)
                            .foregroundColor(filter == f ? .black : Theme.text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(filter == f ? Theme.coral : Theme.surface2)
                            .cornerRadius(18)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private func resultsList(_ r: SearchResults) -> some View {
        List {
            if let top = r.topTrack {
                Section {
                    Button { player.playRemoteTracks([top] + r.tracks, startingAt: 0) } label: {
                        HStack(spacing: 12) {
                            RemoteThumb(url: top.artworkURL, size: 64, cornerRadius: 10)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Top result")
                                    .font(.caption).bold()
                                    .foregroundColor(Theme.coral)
                                Text(top.title)
                                    .foregroundColor(Theme.text).bold()
                                    .lineLimit(1)
                                Text(top.artist)
                                    .foregroundColor(Theme.textDim)
                                    .font(.subheadline)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "play.circle.fill")
                                .font(.title)
                                .foregroundColor(Theme.coral)
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Top result").foregroundColor(Theme.textDim)
                }
                .listRowBackground(Theme.surface)
            }

            if !r.tracks.isEmpty {
                Section {
                    ForEach(Array(r.tracks.enumerated()), id: \.element.id) { idx, track in
                        Button {
                            player.playRemoteTracks(r.tracks, startingAt: idx)
                        } label: {
                            HStack(spacing: 12) {
                                RemoteThumb(url: track.artworkURL)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title)
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                    Text(track.artist)
                                        .foregroundColor(Theme.textDim)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if track.duration > 0 {
                                    Text(Theme.formatTime(track.duration))
                                        .foregroundColor(Theme.textDim)
                                        .font(.caption)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Songs").foregroundColor(Theme.textDim)
                }
                .listRowBackground(Theme.surface)
            }

            if !r.items.isEmpty {
                Section {
                    ForEach(r.items) { item in
                        NavigationLink {
                            BrowseDetailView(item: item)
                        } label: {
                            HStack(spacing: 12) {
                                RemoteThumb(url: item.artworkURL)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .foregroundColor(Theme.text)
                                        .lineLimit(1)
                                    Text(item.subtitle)
                                        .foregroundColor(Theme.textDim)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(kindLabel(item.kind))
                                    .foregroundColor(Theme.cyan)
                                    .font(.caption).bold()
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Albums, artists & playlists").foregroundColor(Theme.textDim)
                }
                .listRowBackground(Theme.surface)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func kindLabel(_ kind: BrowseItem.Kind) -> String {
        switch kind {
        case .album: return "ALBUM"
        case .artist: return "ARTIST"
        case .playlist: return "PLAYLIST"
        case .other: return ""
        }
    }

    private func runSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard !q.isEmpty else {
            results = nil
            error = nil
            searching = false
            return
        }
        searching = true
        error = nil
        searchTask = Task {
            do {
                let r = try await InnerTube.shared.search(query: q, filter: filter)
                guard !Task.isCancelled else { return }
                results = r
                searching = false
            } catch {
                guard !Task.isCancelled else { return }
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? "Search failed. Check your connection."
                searching = false
            }
        }
    }
}
