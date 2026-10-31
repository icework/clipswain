import Foundation
import PaperclipKit

/// The non-secret identity of the archive that produced a notification.
struct InboxScope: Codable, Hashable, Sendable {
    let serverURL: URL
    let accountID: String
    let companyId: String

    init(serverURL: URL, accountID: String, companyId: String) {
        self.serverURL = PaperclipClient.normalize(serverURL)
        self.accountID = accountID
        self.companyId = companyId
    }
}

struct NotificationDestination: Equatable, Sendable {
    var scope: InboxScope?
    var issueId: String?
    var approvalId: String?
    var eventId: String?
    var agentId: String?
    var runId: String?

    init(scope: InboxScope? = nil, issueId: String? = nil, approvalId: String? = nil,
         eventId: String? = nil, agentId: String? = nil, runId: String? = nil) {
        self.scope = scope
        self.issueId = issueId
        self.approvalId = approvalId
        self.eventId = eventId
        self.agentId = agentId
        self.runId = runId
    }

    init?(userInfo: [AnyHashable: Any]) {
        let server = userInfo["serverURL"] as? String
        let account = userInfo["accountID"] as? String
        let company = userInfo["companyId"] as? String
        var scope: InboxScope?
        if ["serverURL", "accountID", "companyId"].contains(where: { userInfo[$0] != nil }) {
            guard let server, let url = URL(string: server), ["http", "https"].contains(url.scheme),
                  url.host != nil,
                  let account, !account.isEmpty, let company, !company.isEmpty else { return nil }
            scope = InboxScope(serverURL: url, accountID: account, companyId: company)
        }
        self.init(scope: scope, issueId: userInfo["issueId"] as? String,
                  approvalId: userInfo["approvalId"] as? String, eventId: userInfo["eventId"] as? String,
                  agentId: userInfo["agentId"] as? String, runId: userInfo["runId"] as? String)
        guard issueId != nil || approvalId != nil || agentId != nil || runId != nil,
              eventId == nil || issueId != nil else { return nil }
    }

    var userInfo: [String: String] {
        var info: [String: String] = [:]
        info["issueId"] = issueId
        info["approvalId"] = approvalId
        info["eventId"] = eventId
        info["agentId"] = agentId
        info["runId"] = runId
        if let scope {
            info["serverURL"] = scope.serverURL.absoluteString
            info["accountID"] = scope.accountID
            info["companyId"] = scope.companyId
        }
        return info
    }
}
