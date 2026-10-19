import SwiftUI

/// Root view: Library + Equalizer tabs with a mini player on top.
struct ContentView: View {
    @EnvironmentObject var player: PlayerService
    @State private var showPlayer = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                LibraryView()
                    .tabItem { Label("Library", systemImage: "music.note.list") }
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
