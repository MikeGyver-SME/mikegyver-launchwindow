import SwiftUI
import WidgetKit

@MainActor
final class LaunchListModel: ObservableObject {
    @Published var launches: [Launch] = LaunchStore.cachedLaunches
    @Published var pinnedID: String? = LaunchStore.pinnedID
    @Published var errorMessage: String?
    @Published var isLoading = false

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            launches = try await LaunchAPI.fetchUpcoming()
            errorMessage = nil
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            errorMessage = "Couldn't refresh launches. Showing cached data."
        }
    }

    func togglePin(_ launch: Launch) {
        if pinnedID == launch.id {
            pinnedID = nil
            LaunchStore.pinnedID = nil
            LiveActivityManager.end()
        } else {
            pinnedID = launch.id
            LaunchStore.pinnedID = launch.id
            // Widget is the countdown until the final hours; a Live
            // Activity started days early is dismissed after ~8h, so it
            // would be gone before liftoff. LiveActivityManager.start
            // enforces the 8h guard; true final-hour auto-start needs
            // push-to-start via APNs (a later step, see README).
            LiveActivityManager.start(for: launch)
        }
    }
}

struct LaunchListView: View {
    @StateObject private var model = LaunchListModel()

    var body: some View {
        NavigationStack {
            List {
                if let error = model.errorMessage {
                    Text(error).font(.footnote).foregroundStyle(.orange)
                }
                ForEach(model.launches) { launch in
                    NavigationLink(value: launch) {
                        LaunchRow(launch: launch, isPinned: model.pinnedID == launch.id)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            model.togglePin(launch)
                        } label: {
                            Label(model.pinnedID == launch.id ? "Unfollow" : "Follow",
                                  systemImage: "pin")
                        }
                        .tint(.blue)
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("Launch Window")
            .navigationDestination(for: Launch.self) { launch in
                LaunchDetailView(launch: launch,
                                 isPinned: model.pinnedID == launch.id,
                                 onTogglePin: { model.togglePin(launch) })
            }
            .overlay {
                if model.isLoading && model.launches.isEmpty { ProgressView() }
            }
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
        }
    }
}

struct LaunchRow: View {
    let launch: Launch
    let isPinned: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if isPinned { Image(systemName: "pin.fill").foregroundStyle(.blue).font(.caption) }
                    Text(launch.shortName).font(.headline).lineLimit(1)
                }
                Text("\(launch.rocket) · \(launch.padName)")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Countdown.tMinus(to: launch.net))
                    .font(.system(.subheadline, design: .monospaced)).bold()
                Text(launch.statusAbbrev).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
