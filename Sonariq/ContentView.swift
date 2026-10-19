import SwiftUI

/// Root view: Home, Library, Queue, Equalizer tabs with a glass mini player.
struct ContentView: View {
    @EnvironmentObject var player: PlayerService
    @State private var showPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                HomeView()
                    .tabItem { Label("Home", systemImage: "house.fill") }
                LibraryView()
                    .tabItem { Label("Library", systemImage: "music.note.list") }
                QueueView()
                    .tabItem { Label("Queue", systemImage: "list.bullet") }
                    .optionalBadge(player.queue.count)
                EqualizerView()
                    .tabItem { Label("Equalizer", systemImage: "slider.horizontal.3") }
            }
            .tint(Theme.coral)

            if player.currentSong != nil {
                MiniPlayerView { showPlayer = true }
                    .padding(.bottom, 4)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPlayer) {
            NowPlayingView()
        }
    }
}

private extension View {
    /// Tab badge that hides itself when the count is zero.
    @ViewBuilder
    func optionalBadge(_ count: Int) -> some View {
        if count > 0 { badge(count) } else { self }
    }
}
