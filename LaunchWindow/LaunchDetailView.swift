import SwiftUI

struct LaunchDetailView: View {
    let launch: Launch
    let isPinned: Bool
    let onTogglePin: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let url = launch.imageURL {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(launch.shortName).font(.title2).bold()
                    Text(launch.provider).foregroundStyle(.secondary)
                }

                // Live-ticking countdown
                Text(launch.net, style: .timer)
                    .font(.system(size: 40, weight: .semibold, design: .monospaced))
                    .monospacedDigit()

                Text(launch.net.formatted(date: .complete, time: .shortened))
                    .font(.subheadline).foregroundStyle(.secondary)

                Group {
                    LabeledContent("Status", value: launch.statusAbbrev)
                    if let precision = launch.netPrecision, !precision.isEmpty {
                        // NET = "no earlier than". A Month/Quarter precision
                        // is not a countdown to the minute; say so.
                        LabeledContent("Time precision", value: precision)
                    }
                    LabeledContent("Rocket", value: launch.rocket)
                    LabeledContent("Pad", value: launch.padName)
                    if !launch.locationName.isEmpty {
                        LabeledContent("Location", value: launch.locationName)
                    }
                }

                if let description = launch.missionDescription, !description.isEmpty {
                    Text(description).font(.body)
                }

                HStack {
                    Button(action: onTogglePin) {
                        Label(isPinned ? "Following" : "Follow",
                              systemImage: isPinned ? "pin.fill" : "pin")
                    }
                    .buttonStyle(.borderedProminent)

                    if let stream = launch.streamURL {
                        Button { openURL(stream) } label: {
                            Label("Watch", systemImage: "play.rectangle")
                        }
                        .buttonStyle(.bordered)
                    }

                    if launch.net.timeIntervalSinceNow < 8 * 3600 {
                        Button {
                            LiveActivityManager.start(for: launch)
                        } label: {
                            Label("Live", systemImage: "dot.radiowaves.left.and.right")
                        }
                        .buttonStyle(.bordered)
                    }
                }
                if launch.net.timeIntervalSinceNow >= 8 * 3600 {
                    Text("Follow pins this launch to the widget. The Live Activity button appears in the final 8 hours; automatic final-hour start needs push-to-start (see README).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}
