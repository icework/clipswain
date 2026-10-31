import Foundation

public struct LLMModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let contextLength: Int?
    public let supportsStructuredOutputs: Bool

    public func matches(_ query: String) -> Bool {
        let terms = query.split(whereSeparator: \.isWhitespace)
        return terms.allSatisfy { id.localizedCaseInsensitiveContains($0) || name.localizedCaseInsensitiveContains($0) }
    }
}

/// Fetches current provider catalogs, rather than shipping an inevitably stale model list.
public struct LLMModelCatalog: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func fetch(kind: LLMProviderKind, apiKey: String, sessionID: String) async throws -> [LLMModel] {
        let request = try makeRequest(kind: kind, apiKey: apiKey, sessionID: sessionID)
        let (data, response) = try await session.data(for: request, delegate: RedirectBlockingDelegate())
        guard let http = response as? HTTPURLResponse else { throw TaskDraftError.unreadable }
        guard (200..<300).contains(http.statusCode) else {
            throw TaskDraftError.http(status: http.statusCode, message: TaskDrafter.errorMessage(from: data))
        }
        return try Self.parse(data)
    }

    func makeRequest(kind: LLMProviderKind, apiKey: String, sessionID: String) throws -> URLRequest {
        guard let url = kind.modelsEndpoint else { throw TaskDraftError.notConfigured }
        try TransportSecurityPolicy.validate(url)
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // Public catalogs also work before entering a key; credentials, when supplied,
        // only go to the preset provider's own endpoint.
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        TaskDrafter.addIntegrationHeaders(to: &request, kind: kind, sessionID: sessionID)
        return request
    }

    public static func parse(_ data: Data) throws -> [LLMModel] {
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let rows = json["data"]?.arrayValue else { throw TaskDraftError.unreadable }
        var seen = Set<String>()
        return rows.compactMap { row -> LLMModel? in
            guard let id = row["id"]?.stringValue, !id.trimmingCharacters(in: .whitespaces).isEmpty,
                  !id.hasSuffix(":batch"),
                  seen.insert(id).inserted else { return nil }
            if let outputs = row["architecture"]?["output_modalities"]?.arrayValue,
               !outputs.contains(.string("text")) { return nil }
            let length: Int?
            if case .number(let number) = row["context_length"], number > 0, number < Double(Int.max) {
                length = Int(number)
            } else { length = nil }
            return LLMModel(id: id, name: row["name"]?.stringValue ?? id, contextLength: length,
                            supportsStructuredOutputs: row["supported_parameters"]?.arrayValue?.contains(.string("structured_outputs")) == true)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
