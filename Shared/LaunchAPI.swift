import Foundation

/// Where a successful launch list came from, for the status line in the app.
enum LaunchSource {
    case worker
    case direct
}

/// The Worker's /health response. It never touches Launch Library 2, so
/// checking it never burns the upstream rate limit and never 429s for
/// an upstream reason. `cache` is "fresh", "stale" or "empty".
struct WorkerHealth: Decodable {
    let status: String
    let cache: String
    let cachedAt: String?
    let ttlSeconds: Int?

    var summary: String {
        switch cache {
        case "fresh": return "Worker OK · fresh cache"
        case "stale": return "Worker OK · stale cache"
        case "empty": return "Worker OK · no cached launches yet"
        default: return "Worker OK · cache: \(cache)"
        }
    }
}

enum LaunchAPI {
    /// Deployed Worker. If the Worker fails (e.g. it returns a 502/429
    /// because Launch Library 2 rate-limited its shared Cloudflare
    /// egress IP), the app falls back to direct LL2 instead of showing
    /// the orange "couldn't refresh" message — see fetchUpcomingWithSource.
    static let workerBaseURL = "https://launchwindow.mikegyver.workers.dev"
    private static let ll2Direct = "https://ll.thespacedevs.com/2.2.0/launch/upcoming/?limit=25&mode=detail"

    /// Backwards-compatible entry point used by the widget: same
    /// Worker-then-direct fallback, source discarded.
    static func fetchUpcoming() async throws -> [Launch] {
        try await fetchUpcomingWithSource().0
    }

    /// Try the Worker first, then direct LL2. The Worker is preferred
    /// because it caches (15 min) and shields the phone's IP from
    /// LL2's 15 req/hr unauthenticated limit, but a blocked Worker
    /// must never be worse than no Worker at all.
    static func fetchUpcomingWithSource() async throws -> ([Launch], LaunchSource) {
        if !workerBaseURL.isEmpty {
            do {
                let launches = try await fetchFrom(workerBaseURL + "/launches")
                return (launches, .worker)
            } catch {
                // Fall through to direct LL2. The error is intentionally
                // not surfaced here: if direct succeeds, the user gets
                // a fresh list and the status line says so.
            }
        }
        let launches = try await fetchFrom(ll2Direct)
        return (launches, .direct)
    }

    /// Worker health, without touching upstream. Returns nil when no
    /// Worker URL is configured, or when the Worker itself is unreachable.
    /// A nil result is not an upstream failure: /health never fetches LL2.
    static func fetchHealth() async -> WorkerHealth? {
        guard !workerBaseURL.isEmpty,
              let url = URL(string: workerBaseURL + "/health") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let health = try? JSONDecoder().decode(WorkerHealth.self, from: data)
        else { return nil }
        return health
    }

    private static func fetchFrom(_ urlString: String) async throws -> [Launch] {
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
