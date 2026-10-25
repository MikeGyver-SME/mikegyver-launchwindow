import Foundation
import ActivityKit

/// App-facing launch model (flattened from the Launch Library 2 payload).
struct Launch: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let net: Date
    let net_precision: String?
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

    let id: String
    let name: String
    let net: Date
    let net_precision: String?
    let status: Status?
    let launch_service_provider: Provider?
    let rocket: Rocket?
    let mission: Mission?
    let pad: Pad?
    let image: String?
    let vidURLs: [Vid]?

    var asLaunch: Launch {
        Launch(
            id: id,
            name: name,
            net: net,
            statusAbbrev: status?.abbrev ?? "TBD",
            provider: launch_service_provider?.name ?? "Unknown",
            rocket: rocket?.configuration?.full_name ?? rocket?.configuration?.name ?? "Unknown rocket",
            netPrecision: net_precision,
            missionName: mission?.name,
            missionDescription: mission?.description,
            padName: pad?.name ?? "Unknown pad",
            locationName: pad?.location?.name ?? "",
            imageURL: image.flatMap(URL.init(string:)),
            streamURL: vidURLs?.compactMap(\.url).first
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
