import WidgetKit
import SwiftUI

struct LaunchEntry: TimelineEntry {
    let date: Date
    let launch: Launch?
}

struct LaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> LaunchEntry {
        LaunchEntry(date: .now, launch: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (LaunchEntry) -> Void) {
        completion(LaunchEntry(date: .now, launch: LaunchStore.featuredLaunch() ?? Self.sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LaunchEntry>) -> Void) {
        Task {
            // Refresh cache (best-effort); fall back to whatever the app cached.
            // Note: these entries are precomputed snapshots, not a live tick.
            // WidgetKit budgets timeline refreshes, so a 1-minute step near
            // T-0 is a request, not a guarantee; the .timer Live Activity
            // is the surface that actually ticks every second.
            _ = try? await LaunchAPI.fetchUpcoming()
            let launch = LaunchStore.featuredLaunch()
            let now = Date()

            // Tighter cadence close to T-0.
            var step: TimeInterval = 15 * 60
            if let net = launch?.net {
                let remaining = net.timeIntervalSince(now)
                if remaining < 3600 { step = 60 } else if remaining < 6 * 3600 { step = 5 * 60 }
            }

            let entries = (0..<20).map { i in
                LaunchEntry(date: now.addingTimeInterval(Double(i) * step), launch: launch)
            }
            completion(Timeline(entries: entries, policy: .after(entries.last!.date)))
        }
    }

    static let sample = Launch(
        id: "sample", name: "Falcon 9 Block 5 | Starlink Group 10-5",
        net: .now.addingTimeInterval(2 * 86_400 + 4 * 3_600),
        netPrecision: "Day",
        statusAbbrev: "Go", provider: "SpaceX", rocket: "Falcon 9 Block 5",
        missionName: "Starlink Group 10-5", missionDescription: nil,
        padName: "SLC-40", locationName: "Cape Canaveral, FL, USA",
        imageURL: nil, streamURL: nil)
}

struct LaunchCountdownWidget: Widget {
    let kind = "LaunchCountdownWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LaunchProvider()) { entry in
            LaunchWidgetView(entry: entry)
                .containerBackground(
                    LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.14),
                                            Color(red: 0.10, green: 0.14, blue: 0.30)],
                                   startPoint: .top, endPoint: .bottom),
                    for: .widget)
        }
        .configurationDisplayName("Next Launch")
        .description("Countdown to your followed launch, or the next one up.")
        .supportedFamilies([.systemSmall, .systemMedium,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct LaunchWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LaunchEntry

    var body: some View {
        if let launch = entry.launch {
            switch family {
            case .systemSmall: small(launch)
            case .systemMedium: medium(launch)
            case .accessoryCircular: circular(launch)
            case .accessoryRectangular: rectangular(launch)
            case .accessoryInline:
                Text("\(Countdown.tMinus(to: launch.net, from: entry.date)) \(launch.shortName)")
            default: small(launch)
            }
        } else {
            Text("No upcoming launches").font(.caption)
        }
    }

    private func small(_ l: Launch) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NEXT LAUNCH").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
            Text(l.shortName).font(.footnote).bold().lineLimit(2)
            Spacer(minLength: 0)
            Text(Countdown.tMinus(to: l.net, from: entry.date))
                .font(.system(.title2, design: .monospaced)).bold()
                .minimumScaleFactor(0.6)
            Text(l.statusAbbrev).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func medium(_ l: Launch) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NEXT LAUNCH").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                Text(l.shortName).font(.headline).lineLimit(2)
                Text(l.rocket).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(l.padName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(Countdown.tMinus(to: l.net, from: entry.date))
                    .font(.system(.title, design: .monospaced)).bold()
                    .minimumScaleFactor(0.6)
                Text(l.net.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func circular(_ l: Launch) -> some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "airplane.departure").font(.caption2)
                Text(Countdown.tMinus(to: l.net, from: entry.date)
                        .replacingOccurrences(of: "T-", with: ""))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
            }
        }
    }

    private func rectangular(_ l: Launch) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(l.shortName).font(.caption).bold().lineLimit(1)
            Text(Countdown.tMinus(to: l.net, from: entry.date))
                .font(.system(.title3, design: .monospaced)).bold()
            Text(l.padName).font(.caption2).lineLimit(1)
        }
    }
}
