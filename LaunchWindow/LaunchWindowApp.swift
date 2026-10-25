import SwiftUI

@main
struct LaunchWindowApp: App {
    var body: some Scene {
        WindowGroup {
            LaunchListView()
                .preferredColorScheme(.dark)
        }
    }
}
