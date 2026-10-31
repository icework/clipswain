import Foundation

public struct IssueDocumentSummary: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var companyId: String
    public var issueId: String
    public var key: String
    public var title: String?
    public var latestRevisionNumber: Int
    public var updatedAt: Date

    public var displayTitle: String { title?.isEmpty == false ? title! : key }
}

public struct IssueDocument: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var companyId: String
    public var issueId: String
    public var key: String
    public var title: String?
    public var body: String
    public var latestRevisionNumber: Int
    public var updatedAt: Date
}

public struct IssueAttachment: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var companyId: String
    public var issueId: String
    public var originalFilename: String?
    public var contentType: String
    public var byteSize: Int64
    public var createdAt: Date

    public var displayName: String { originalFilename?.isEmpty == false ? originalFilename! : id }
}

/// Strings intentionally accept new server types/statuses without breaking the entire list.
public struct IssueWorkProduct: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var companyId: String
    public var issueId: String
    public var type: String
    public var title: String
    public var url: String?
    public var status: String
    public var isPrimary: Bool
    public var summary: String?
    public var metadata: JSONValue?
    public var updatedAt: Date

    /// Server-local paths and non-web schemes cannot be opened as files on this iPhone.
    public var webURL: URL? {
        guard let url, let parsed = URL(string: url),
              ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
              parsed.host != nil, parsed.user == nil, parsed.password == nil else { return nil }
        return parsed
    }
}
