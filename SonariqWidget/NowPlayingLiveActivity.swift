import ActivityKit
import WidgetKit
import SwiftUI

/// Sonariq on the lock screen and the Dynamic Island.
struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SonariqActivityAttributes.self) { context in
            HStack(spacing: 12) {
                if let data = context.state.artworkData,
                   let ui = UIImage(data: data) {
                    Image(uiImage: ui)
                        .resizable()
                        .frame(width: 52, height: 52)
                        .cornerRadius(10)
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.secondary.opacity(0.3))
                        .frame(width: 52, height: 52)
                        .overlay(Image(systemName: "music.note"))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(context.state.artist)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    ProgressView(value: context.state.progress,
                                 total: max(context.state.duration, 1))
                }
                Spacer()
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.title)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.artist)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(value: context.state.progress,
                                 total: max(context.state.duration, 1))
                }
            } compactLeading: {
                Image(systemName: "music.note")
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
            } minimal: {
                Image(systemName: "music.note")
            }
        }
    }
}
