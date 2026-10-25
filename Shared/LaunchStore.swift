import Foundation
import WidgetKit

/// Shared persistence via the App Group so the app and widget see the same data.
enum LaunchStore {
    static let groupID = "group.studio.mikegyver.launchwindow"
    /// Nil when the App Group is not entitled on this target/profile.
    /// UserDefaults(suiteName:) returns nil in that case; falling back to
    /// .standard would silently split app and widget state, so callers
    /// must not treat a .standard fallback as shared state.
    static var groupReachable: Bool { UserDefaults(suiteName: groupID) != nil }
    private static let defaults = UserDefaults(suiteName: groupID) ?? .standard
    private static let pinnedKey = "pinnedLaunchID"
    private static let cacheKey = "cachedLaunches"

    static var pinnedID: String? {
        get {
            CFPreferencesAppSynchronize(groupID as CFString)
            return defaults.string(forKey: pinnedKey)
        }
        set {
            defaults.set(newValue, forKey: pinnedKey)
            CFPreferencesAppSynchronize(groupID as CFString)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    static var cachedLaunches: [Launch] {
        get {
            CFPreferencesAppSynchronize(groupID as CFString)
            guard let data = defaults.data(forKey: cacheKey),
                  let launches = try? JSONDecoder.ll2Stored.decode([Launch].self, from: data)
            else { return [] }
            return launches
        }
        set {
            if let data = try? JSONEncoder.ll2Stored.encode(newValue) {
                defaults.set(data, forKey: cacheKey)
                CFPreferencesAppSynchronize(groupID as CFString)
                WidgetCenter.shared.reloadAllTimelines()
            }
        }
    }

    /// The pinned launch if it is still upcoming, otherwise the next launch in the cache.
    static func featuredLaunch(now: Date = .now) -> Launch? {
        let upcoming = cachedLaunches.filter { $0.net > now.addingTimeInterval(-3600) }
        if let id = pinnedID, let pinned = upcoming.first(where: { $0.id == id }) {
            return pinned
        }
        return upcoming.sorted { $0.net < $1.net }.first
    }
}

extension JSONEncoder {
    static let ll2Stored: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let ll2Stored: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
