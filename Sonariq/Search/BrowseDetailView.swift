import SwiftUI

/// Album / artist / playlist page: header plus the full track list, all
/// playable through the engine.
struct BrowseDetailView: View {
    @EnvironmentObject var player: PlayerService
    let item: BrowseItem

    @State private var result: BrowseResult?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if loading {
                ProgressView().tint(Theme.coral)
            } else if let error {
                Text(error)
                    .foregroundColor(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .padding()
            } else if let result {
                List {
                    Section {
                        HStack(spacing: 16) {
                            RemoteThumb(url: result.artworkURL ?? item.artworkURL,
                                        size: 120, cornerRadius: 12)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(result.title.isEmpty ? item.title : result.title)
                                    .foregroundColor(Theme.text)
                                    .font(.title3).bold()
                                    .lineLimit(3)
                                if !result.subtitle.isEmpty {
                                    Text(result.subtitle)
                                        .foregroundColor(Theme.textDim)
                                        .font(.subheadline)
                                        .lineLimit(3)
                                }
                                Text("\(result.tracks.count) songs")
                                    .foregroundColor(Theme.cyan)
                                    .font(.caption).bold()
                            }
                            Spacer()
                        }
                        .padding(.vertical, 8)

                        if !result.tracks.isEmpty {
                            Button {
                                player.playRemoteTracks(result.tracks, startingAt: 0)
                            } label: {
                                Label("Play all", systemImage: "play.fill")
                                    .bold()
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(Theme.coral)
                                    .cornerRadius(12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(Theme.surface)

                    if !result.tracks.isEmpty {
                        Section {
                            ForEach(Array(result.tracks.enumerated()), id: \.element.id) { idx, track in
                                Button {
                                    player.playRemoteTracks(result.tracks, startingAt: idx)
                                } label: {
                                    HStack(spacing: 12) {
                                        Text("\(idx + 1)")
                                            .foregroundColor(Theme.textDim)
                                            .font(.subheadline)
                                            .frame(width: 24)
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
                            Text("Tracks").foregroundColor(Theme.textDim)
                        }
                        .listRowBackground(Theme.surface)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        do {
            result = try await InnerTube.shared.browse(browseId: item.browseId)
            loading = false
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't open this page."
            loading = false
        }
    }
}
