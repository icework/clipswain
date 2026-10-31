import Foundation

/// Applies equally to app connections and direct SDK callers. HTTP requires explicit consent.
public enum TransportSecurityPolicy {
    public static func validate(_ url: URL, allowInsecureHTTP: Bool = false) throws {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme) else {
            throw TransportSecurityError.unsupportedScheme
        }
        guard let host = url.host, !host.isEmpty else { throw TransportSecurityError.missingHost }
        guard url.user == nil, url.password == nil else { throw TransportSecurityError.embeddedCredentials }
        guard scheme != "http" || allowInsecureHTTP else { throw TransportSecurityError.insecureHTTP }
    }
}

public enum TransportSecurityError: LocalizedError, Equatable, Sendable {
    case unsupportedScheme
    case missingHost
    case embeddedCredentials
    case insecureHTTP
    case differentOrigin

    public var errorDescription: String? {
        switch self {
        case .unsupportedScheme: return KitL10n.string("transport.error.unsupported_scheme", defaultValue: "Use an http:// or https:// server address.")
        case .missingHost: return KitL10n.string("transport.error.missing_host", defaultValue: "The server address must include a host.")
        case .embeddedCredentials: return KitL10n.string("transport.error.embedded_credentials", defaultValue: "Remove the username and password from the server address.")
        case .insecureHTTP: return KitL10n.string("transport.error.insecure_http", defaultValue: "HTTP sends credentials and task content without encryption. Explicitly allow HTTP for this connection, or use HTTPS.")
        case .differentOrigin: return KitL10n.string("transport.error.different_origin", defaultValue: "Authenticated content must come from the connected server.")
        }
    }
}

/// URLSession otherwise forwards custom authentication headers and POST bodies on redirects.
/// Reject every redirect, including same-origin redirects, before any second request is sent.
final class RedirectBlockingDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
