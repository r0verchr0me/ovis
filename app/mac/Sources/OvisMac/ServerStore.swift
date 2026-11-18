import Foundation

/// Persisted list of remote Ovis servers the user has added.
/// Mirrors iOS's PCStore but simplified for the Mac app's needs.
@MainActor
final class ServerStore {
    private static let defaults = UserDefaults.standard
    private static let serversKey = "ovis.remoteServers"
    private static let currentKey = "ovis.currentServer"
    private static let lastKey = "ovis.lastServer"

    struct Server: Codable, Equatable {
        let id: String          // The server_id from the relay offer
        let name: String        // User-friendly name
        let origin: String      // The base origin (e.g., "https://app.ovis.sh/s/<server_id>/")
        let offer: String?      // The full relay offer URL (with #offer= fragment), for re-pairing
        let addedAt: Date
        var lastUsedAt: Date?

        static func from(offerURL: String, name: String? = nil) -> Server? {
            guard let url = URL(string: offerURL),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                  let fragment = components.fragment,
                  fragment.hasPrefix("offer=") else { return nil }

            let payload = String(fragment.dropFirst(6))
            guard let data = Data(base64URLEncoded: payload),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let serverId = json["server_id"] as? String,
                  let relay = json["relay"] as? String else { return nil }

            // The origin for the hosted shell is the app base + /s/<server_id>/
            let appBase = "https://app.ovis.sh"
            let origin = "\(appBase)/s/\(serverId)/"

            return Server(
                id: serverId,
                name: name ?? serverId,
                origin: origin,
                offer: offerURL,
                addedAt: Date(),
                lastUsedAt: nil
            )
        }
    }

    static var servers: [Server] {
        get {
            guard let data = defaults.data(forKey: serversKey),
                  let decoded = try? JSONDecoder().decode([Server].self, from: data) else { return [] }
            return decoded
        }
        set {
            let data = try? JSONEncoder().encode(newValue)
            defaults.set(data, forKey: serversKey)
        }
    }

    static var current: String? {
        get { defaults.string(forKey: currentKey) }
        set { defaults.set(newValue, forKey: currentKey) }
    }

    static var last: String? {
        get { defaults.string(forKey: lastKey) }
        set { defaults.set(newValue, forKey: lastKey) }
    }

    static func add(_ server: Server) {
        var list = servers
        list.removeAll { $0.id == server.id }
        list.insert(server, at: 0)
        servers = list
        current = server.id
        last = server.id
    }

    static func remove(_ id: String) {
        servers = servers.filter { $0.id != id }
        if current == id { current = nil }
        if last == id { last = nil }
    }

    static func use(_ id: String) {
        if var server = servers.first(where: { $0.id == id }) {
            server.lastUsedAt = Date()
            servers = servers.map { $0.id == id ? server : $0 }
            current = id
            last = id
        }
    }

    static func server(id: String) -> Server? {
        servers.first { $0.id == id }
    }

    static func server(origin: String) -> Server? {
        servers.first { $0.origin == origin }
    }
}

extension Data {
    init?(base64URLEncoded string: String) {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        self.init(base64Encoded: base64)
    }
}