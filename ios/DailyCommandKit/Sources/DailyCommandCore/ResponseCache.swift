import CryptoKit
import Foundation

/// Last-known responses for the read actions, kept on disk so every screen opens instantly with
/// what it showed last time and then refreshes from the service. Scoped per user, protected until
/// first unlock, excluded from backups, and wiped on sign-out. Journal entries are stored here
/// exactly as the service sends them: encrypted (`enc:v1:`) when the notebook is locked.
public protocol ResponseCaching: Sendable {
    func read(_ key: String) -> JSON?
    func write(_ key: String, _ json: JSON)
    func clear()
}

public final class ResponseCache: ResponseCaching, @unchecked Sendable {
    private let dir: URL
    private let queue = DispatchQueue(label: "dc.cache", qos: .utility)

    public init(userId: String, root: URL? = nil) {
        let base = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        dir = base.appendingPathComponent("DailyCommand/cache/\(ResponseCache.hash(userId))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var d = dir; try? d.setResourceValues(values)
    }

    /// Stable key for an action and its parameters.
    public static func key(_ action: String, _ params: [String: Any]) -> String {
        let canon = (try? JSONSerialization.data(withJSONObject: params, options: [.sortedKeys])) ?? Data()
        return action + "-" + hash(String(decoding: canon, as: UTF8.self))
    }

    static func hash(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    public func read(_ key: String) -> JSON? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(key + ".json")) else { return nil }
        return try? JSON(data: data)
    }

    public func write(_ key: String, _ json: JSON) {
        guard let data = try? json.data() else { return }
        let url = dir.appendingPathComponent(key + ".json")
        queue.async {
            try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    public func clear() {
        queue.sync { try? FileManager.default.removeItem(at: dir) }
    }
}

public final class MemoryResponseCache: ResponseCaching, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: JSON] = [:]
    public init() {}
    public func read(_ key: String) -> JSON? { lock.withLock { store[key] } }
    public func write(_ key: String, _ json: JSON) { lock.withLock { store[key] = json } }
    public func clear() { lock.withLock { store = [:] } }
}
