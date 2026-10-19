import SwiftUI
import AVFoundation

/// Sonariq for iOS — entry point.
@main
struct SonariqApp: App {
    @StateObject private var player = PlayerService()

    init() {
        configureAudioSession()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
        }
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Sonariq: audio session failed: \(error)")
        }
    }
}
