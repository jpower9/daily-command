import Foundation

/// Sends one HTTP request. URLSession in the app; a fake in tests.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

public struct URLSessionTransport: HTTPTransport {
    let session: URLSession

    public init(timeout: TimeInterval = 60) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = ["Accept": "application/json"]
        session = URLSession(configuration: config)
    }

    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

public enum APIError: LocalizedError, Equatable, Sendable {
    case notConfigured
    case notSignedIn
    /// The account has an authenticator app (TOTP) enrolled; the session must complete that step.
    case twoStepRequired
    case server(status: Int, message: String)
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .notConfigured: "This build isn't set up to reach Daily Command."
        case .notSignedIn: "You're signed out. Sign in to continue."
        case .twoStepRequired: "Enter the code from your authenticator app to continue."
        case let .server(status, message): message.isEmpty ? "Service error (\(status))." : message
        case .emptyResponse: "The server returned an empty response."
        }
    }

    public var status: Int? {
        if case let .server(status, _) = self { return status }
        return nil
    }
}
