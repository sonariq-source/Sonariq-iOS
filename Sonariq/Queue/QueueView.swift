import SwiftUI

/// The live playback queue: jump to any song, reorder, remove.
struct QueueView: View {
    @EnvironmentObject var player: PlayerService

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if player.queue.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "list.bullet")
                            .font(.largeTitle)
                            .foregroundColor(Theme.textDim)
                        Text("Nothing in the queue.")
                            .foregroundColor(Theme.textDim)
                        Text("Play something from your library and it will show up here.")
                            .font(.caption)
                            .foregroundColor(Theme.textDim)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(Array(player.queue.enumerated()), id: \.element.id) { index, song in
                            Button {
                                player.play(songs: player.queue, startingAt: index)
                            } label: {
                                HStack(spacing: 12) {
                                    ArtworkThumb(song: song)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(song.title)
                                            .foregroundColor(isCurrent(index) ? Theme.coral : Theme.text)
                                            .bold(isCurrent(index))
                                            .lineLimit(1)
                                        Text(song.artist)
                                            .font(.caption)
                                            .foregroundColor(Theme.textDim)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    if isCurrent(index) {
                                        Image(systemName: "waveform")
                                            .foregroundColor(Theme.coral)
                                            .font(.caption)
                                    }
                                }
                            }
                            .listRowBackground(Theme.surface)
                        }
                        .onMove(perform: player.move)
                        .onDelete(perform: player.remove)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            EditButton()
                                .foregroundColor(Theme.coral)
                        }
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Clear") { player.clearQueue() }
                                .foregroundColor(Theme.textDim)
                        }
                    }
                }
            }
            .navigationTitle("Queue")
        }
    }

    private func isCurrent(_ index: Int) -> Bool {
        player.currentIndex == index
    }
}
