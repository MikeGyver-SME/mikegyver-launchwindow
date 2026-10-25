import Foundation

enum LaunchAPI {
    /// Paste the deployed Worker URL here BEFORE building for TestFlight.
    /// If left empty, the app AND the widget each call Launch Library 2
    /// directly, and together they can burn the 15 req/hr unauthenticated
    /// limit (see README). Deploy worker/ first, then set this, then build.
    static let workerBaseURL = ""  // e.g. "https://launchwindow.<you>.workers.dev"
    private static let ll2Direct = "https://ll.thespacedevs.com/2.2.0/launch/upcoming/?limit=25&mode=detail"

    static func fetchUpcoming() async throws -> [Launch] {
        let urlString = workerBaseURL.isEmpty ? ll2Direct : workerBaseURL + "/launches"
        guard let url = URL(string: urlString) else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder.ll2.decode(LL2Response.self, from: data)
        let launches = decoded.results.map(\.asLaunch).sorted { $0.net < $1.net }
        LaunchStore.cachedLaunches = launches
        return launches
    }
}
