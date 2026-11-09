import Foundation
import Security

/// A signed-in user's tokens, kept in the Keychain between launches.
public struct Session: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String
    public var userId: String
    public var email: String

    public init(accessToken: String, refreshToken: String, userId: String, email: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.userId = userId
        self.email = email
    }
}

/// Where the session is kept. The app uses the Keychain; tests use memory.
public protocol SessionStore: Sendable {
    func load() -> Session?
    func save(_ session: Session)
    func clear()
}

/// Keychain storage: one generic-password item, readable after first unlock,
/// never synced to other devices. Daily Command has no extension today; the
/// access-group plumbing stays so one can be added without a migration.
public struct KeychainSessionStore: SessionStore {
    public let service: String
    public let account: String
    public let accessGroup: String?

    public init(service: String = "com.execclone.dailycommand.session", account: String = "default", accessGroup: String? = nil) {
        self.service = service
        self.account = account
        self.accessGroup = accessGroup
    }

    /// The shared group named in the bundle's Info.plist (`DCKeychainGroup`).
    public static func shared(bundle: Bundle = .main) -> KeychainSessionStore {
        let group = (bundle.object(forInfoDictionaryKey: "DCKeychainGroup") as? String).flatMap { $0.hasPrefix("$(") ? nil : $0 }
        return KeychainSessionStore(accessGroup: group)
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> Session? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(Session.self, from: data)
    }

    public func save(_ session: Session) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        clear()
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        if let accessGroup { add[kSecAttrAccessGroup as String] = accessGroup }
        if SecItemAdd(add as CFDictionary, nil) == errSecMissingEntitlement, accessGroup != nil {
            // Unsigned test builds lack the sharing entitlement; keep the app working.
            add.removeValue(forKey: kSecAttrAccessGroup as String)
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public func clear() {
        // Deletes the item in every group this process can reach.
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// In-memory store for tests and previews.
public final class MemorySessionStore: SessionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Session?
    public init(_ session: Session? = nil) { value = session }
    public func load() -> Session? { lock.withLock { value } }
    public func save(_ session: Session) { lock.withLock { value = session } }
    public func clear() { lock.withLock { value = nil } }
}
