import ActivityKit
import WidgetKit
import SwiftUI

struct LaunchLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LaunchActivityAttributes.self) { context in
            // Lock Screen / banner
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.attributes.missionName).font(.headline).lineLimit(1)
                    Text(context.attributes.rocket).font(.caption).foregroundStyle(.secondary)
                    Text(context.state.status).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(context.state.net, style: .timer)
                    .font(.system(.title, design: .monospaced)).bold()
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.04, green: 0.06, blue: 0.14))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.attributes.missionName).font(.caption).lineLimit(2)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.net, style: .timer)
                        .font(.system(.title3, design: .monospaced)).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("\(context.attributes.rocket) · \(context.state.status)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "airplane.departure")
            } compactTrailing: {
                Text(context.state.net, style: .timer)
                    .monospacedDigit().frame(width: 52)
            } minimal: {
                Image(systemName: "airplane.departure")
            }
        }
    }
}
