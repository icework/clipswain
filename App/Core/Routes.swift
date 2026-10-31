import SwiftUI

struct IssueRoute: Hashable { let id: String }
struct AgentRoute: Hashable { let id: String }
struct ApprovalRoute: Hashable { let id: String }
struct RunRoute: Hashable { let id: String }

extension View {
    /// Registers every detail screen so any tab's stack can push tasks, agents and approvals.
    /// Each screen is keyed by its id: when a deep link replaces one task with another at the
    /// same stack position, SwiftUI would otherwise reuse the old screen and its loaded state.
    func paperclipDestinations() -> some View {
        navigationDestination(for: IssueRoute.self) { TaskDetailView(issueId: $0.id).id($0.id) }
            .navigationDestination(for: AgentRoute.self) { AgentDetailView(agentId: $0.id).id($0.id) }
            .navigationDestination(for: ApprovalRoute.self) { ApprovalDetailView(approvalId: $0.id).id($0.id) }
            .navigationDestination(for: RunRoute.self) { RunDetailView(runId: $0.id).id($0.id) }
    }
}
