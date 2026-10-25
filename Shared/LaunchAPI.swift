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
    // Present on Worker builds with the 429 backoff; absent on older ones.
    let blocked: Bool?
    let blockedUntil: String?

    var summary: String {
        let base: String
        switch cache {
        case "fresh": base = "Worker OK · fresh cache"
        case "stale": base = "Worker OK · stale cache"
        case "empty": base = "Worker OK · no cached launches yet"
        default: base = "Worker OK · cache: \(cache)"
        }
        if blocked == true { return "\(base) · blocked (no upstream fetch)" }
        return base
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

    /// Health-first, so the app never keeps the Worker blocked.
    /// A /health check never touches LL2, so it is safe on every refresh.
    /// - If the Worker cache is fresh, use the Worker: it serves cache
    ///   with no upstream fetch at all, so it burns nothing.
    /// - Otherwise (empty, stale, or Worker unreachable), use direct LL2
    ///   first. Hitting Worker /launches when its cache is empty or stale
    ///   would make the Worker fetch upstream and burn the shared
    ///   Cloudflare egress IP's 15/hr budget — every app open and widget
    ///   refresh doing that is exactly how the rolling window stays full
    ///   forever. Only if direct fails do we try the Worker as a last
    ///   resort, where it may serve a stale cached list.
    /// The Worker only ever primes deliberately: a single manual
    /// /launches hit after /throttle shows a free slot, after which
    /// health turns fresh and the app uses the Worker again.
    static func fetchUpcomingWithSource() async throws -> ([Launch], LaunchSource) {
        if !workerBaseURL.isEmpty {
            let health = await fetchHealth()
            if health?.cache == "fresh" {
                do {
                    let launches = try await fetchFrom(workerBaseURL + "/launches")
                    return (launches, .worker)
                } catch {
                    let launches = try await fetchFrom(ll2Direct)
                    return (launches, .direct)
                }
            } else {
                do {
                    let launches = try await fetchFrom(ll2Direct)
                    return (launches, .direct)
                } catch let directError {
                    // Last resort: the Worker may have a stale list
                    // even though direct LL2 just failed.
                    do {
                        let launches = try await fetchFrom(workerBaseURL + "/launches")
                        return (launches, .worker)
                    } catch {
                        throw directError
                    }
                }
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
