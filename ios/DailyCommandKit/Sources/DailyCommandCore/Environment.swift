import Foundation

/// Where the app's API lives. The values come from the app's Info.plist
/// (`DCSupabaseURL`, `DCSupabasePublishableKey`), which the build fills from
/// Config/Local.xcconfig — nothing key-like lives in source.
///
/// The publishable key grants nothing by itself: every API action verifies the
/// signed-in user's token on the server (ExecClone's mobile-bootstrap function).
public struct ServiceEnvironment: Sendable, Equatable {
    public var baseURL: URL
    public var publishableKey: String

    public init(baseURL: URL, publishableKey: String) {
        self.baseURL = baseURL
        self.publishableKey = publishableKey
    }

    public static let infoURLKey = "DCSupabaseURL"
    public static let infoKeyKey = "DCSupabasePublishableKey"

    /// Reads the environment from a bundle's Info.plist. Fails closed: a build
    /// without the values can't sign in instead of calling the wrong project.
    public static func fromBundle(_ bundle: Bundle = .main) -> ServiceEnvironment? {
        guard let urlString = bundle.object(forInfoDictionaryKey: infoURLKey) as? String,
              let url = URL(string: urlString), url.scheme == "https",
              let key = bundle.object(forInfoDictionaryKey: infoKeyKey) as? String,
              !key.isEmpty, !key.hasPrefix("$(")
        else { return nil }
        return ServiceEnvironment(baseURL: url, publishableKey: key)
    }

    /// The one client API endpoint (contract/client-api.md in execclone-apps).
    public var appAPIURL: URL { baseURL.appendingPathComponent("functions/v1/mobile-bootstrap") }

    public func authURL(_ path: String) -> URL {
        // `path` may carry a query string, so build from a string, not path components.
        URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/auth/v1/" + path)!
    }
}

/// Fixed product links.
public enum DailyCommandLinks {
    public static let privacyPolicy = URL(string: "https://execclone.com/privacy/")!
    public static let terms = URL(string: "https://execclone.com/terms/")!
    public static let website = URL(string: "https://execclone.com/daily-command/")!
    public static let support = URL(string: "https://execclone.com/support/")!
    /// Executive OS, where ExecClone clients use the same planner.
    public static let executiveOS = URL(string: "https://app.execclone.com/app/command")!
}
