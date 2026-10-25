import Foundation
import ActivityKit

/// App-facing launch model (flattened from the Launch Library 2 payload).
struct Launch: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let net: Date
    let statusAbbrev: String
    let provider: String
    let rocket: String
    let missionName: String?
    let missionDescription: String?
    let netPrecision: String?
    let padName: String
    let locationName: String
    let imageURL: URL?
    let streamURL: URL?

    var shortName: String {
        // LL2 names look like "Falcon 9 Block 5 | Starlink Group 10-5"
        name.components(separatedBy: " | ").last ?? name
    }
}

/// Live Activity payload.
struct LaunchActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var net: Date
        var status: String
    }
    var launchID: String
    var missionName: String
    var rocket: String
}

// MARK: - Launch Library 2 decoding

struct LL2Response: Decodable { let results: [LL2Launch] }

struct LL2Launch: Decodable {
    struct Status: Decodable { let abbrev: String? }
    struct Provider: Decodable { let name: String? }
    struct Rocket: Decodable {
        struct Config: Decodable { let full_name: String?; let name: String? }
        let configuration: Config?
    }
    struct Mission: Decodable { let name: String?; let description: String? }
    struct Pad: Decodable {
        struct Location: Decodable { let name: String? }
        let name: String?
        let location: Location?
    }
    struct Vid: Decodable { let url: URL? }
    // LL2 net_precision is an OBJECT, not a string:
    // { "id": 1, "name": "Minute", "abbrev": "MIN" }.
    // Decoding it as String? fails every launch, which fails the
    // whole list — that was the "Couldn't refresh launches" bug.
    struct NetPrecision: Decodable { let name: String?; let abbrev: String? }

    let id: String
    let name: String
    let net: Date
    let net_precision: NetPrecision?
    let status: Status?
    let launch_service_provider: Provider?
    let rocket: Rocket?
    let mission: Mission?
    let pad: Pad?
    let image: String?
    // LL2 uses snake_case vid_urls; keep both spellings so a stream
    // link works whichever key the payload uses. Either one missing
    // is fine (optional) — it just means no Watch button, not a
    // failed list.
    let vidURLs: [Vid]?
    let vid_urls: [Vid]?

    var asLaunch: Launch {
        Launch(
            id: id,
            name: name,
            net: net,
            statusAbbrev: status?.abbrev ?? "TBD",
            provider: launch_service_provider?.name ?? "Unknown",
            rocket: rocket?.configuration?.full_name ?? rocket?.configuration?.name ?? "Unknown rocket",
            missionName: mission?.name,
            missionDescription: mission?.description,
            netPrecision: net_precision?.name ?? net_precision?.abbrev,
            padName: pad?.name ?? "Unknown pad",
            locationName: pad?.location?.name ?? "",
            imageURL: image.flatMap(URL.init(string:)),
            streamURL: vidURLs?.compactMap(\.url).first ?? vid_urls?.compactMap(\.url).first
        )
    }
}

extension JSONDecoder {
    static let ll2: JSONDecoder = {
        let d = JSONDecoder()
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let date = withFrac.date(from: s) ?? plain.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Bad date: \(s)"))
        }
        return d
    }()
}
