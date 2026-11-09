import Foundation
import Supabase

/// Supabase connection, read from Resources/Supabase.plist.
/// While that file holds placeholders, `client` is nil and the app runs on this device only.
enum Backend {
    struct Config {
        let url: URL
        let anonKey: String
        let webBaseURL: URL?
    }

    static let config: Config? = {
        guard
            let fileURL = Bundle.main.url(forResource: "Supabase", withExtension: "plist"),
            let dict = NSDictionary(contentsOf: fileURL) as? [String: String],
            let urlString = dict["SUPABASE_URL"], !urlString.contains("YOUR-"),
            let url = URL(string: urlString),
            let key = dict["SUPABASE_ANON_KEY"], !key.contains("YOUR-"), !key.isEmpty
        else { return nil }
        let web = dict["WEB_BASE_URL"].flatMap { $0.contains("YOUR-") ? nil : URL(string: $0) }
        return Config(url: url, anonKey: key, webBaseURL: web)
    }()

    static let client: SupabaseClient? = config.map { c in
        SupabaseClient(
            supabaseURL: c.url,
            supabaseKey: c.anonKey,
            options: SupabaseClientOptions(
                db: .init(encoder: JSONCoding.encoder, decoder: JSONCoding.decoder)
            )
        )
    }

    static var isConfigured: Bool { client != nil }

    /// Link that opens the join screen: the web guest page when configured (it hands off to the
    /// app if installed), otherwise the app's own URL scheme.
    static func joinURL(code: String) -> URL {
        if let web = config?.webBaseURL {
            return web.appending(path: "join").appending(path: code)
        }
        return URL(string: "sharedspace://join/\(code)")!
    }

    /// Extracts a room code from sharedspace://join/K7M2Q or https://…/join/K7M2Q.
    static func roomCode(from url: URL) -> String? {
        let parts = ([url.host()].compactMap { $0 } + url.pathComponents).filter { $0 != "/" }
        guard let i = parts.firstIndex(of: "join"), i + 1 < parts.count else { return nil }
        let code = RoomCode.normalize(parts[i + 1])
        return code.count == 5 ? code : nil
    }
}

/// The person using this device.
enum Identity {
    private static let nameKey = "ss.name"
    private static let userIdKey = "ss.userId"

    static var name: String {
        get { UserDefaults.standard.string(forKey: nameKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: nameKey) }
    }

    /// Stable id for this device. Replaced by the Supabase user id after the first sign-in.
    static var userId: UUID {
        get {
            if let s = UserDefaults.standard.string(forKey: userIdKey), let id = UUID(uuidString: s) { return id }
            let id = UUID()
            UserDefaults.standard.set(id.uuidString, forKey: userIdKey)
            return id
        }
        set { UserDefaults.standard.set(newValue.uuidString, forKey: userIdKey) }
    }
}
