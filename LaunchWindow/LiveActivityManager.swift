import ActivityKit
import Foundation

/// Starts/ends the Lock Screen + Dynamic Island Live Activity for a launch.
/// NOTE: started locally here (manual "Live" button). For auto-start near T-0 you'd
/// push updates via APNs from the Worker (push-to-start), which is a later step.
enum LiveActivityManager {
    static func start(for launch: Launch) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // Live Activities live at most ~8h. Starting one days ahead does
        // not give you a final-hour countdown, it gives you a dead one.
        guard launch.net.timeIntervalSinceNow < 8 * 3600 else { return }
        end()
        let attributes = LaunchActivityAttributes(
            launchID: launch.id,
            missionName: launch.shortName,
            rocket: launch.rocket
        )
        let state = LaunchActivityAttributes.ContentState(net: launch.net, status: launch.statusAbbrev)
        let content = ActivityContent(state: state, staleDate: launch.net.addingTimeInterval(3600))
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
    }

    static func end() {
        for activity in Activity<LaunchActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
