import PaperclipKit
import SwiftUI

struct AgentListView: View {
    @Environment(AppModel.self) private var app

    enum Mode: String, CaseIterable, Identifiable {
        case gallery, org
        var id: String { rawValue }
        var label: String { self == .gallery ? AgentsL10n.text("list.team", "Team") : AgentsL10n.text("list.org_chart", "Organization") }
    }

    @State private var mode = Mode.gallery
    @State private var org: [OrgNode] = []
    @State private var showTerminated = false
    @State private var hiring = false
    @State private var path = NavigationPath()

    private var agents: [Agent] {
        app.agents
            .filter { showTerminated || $0.status != .terminated }
            .sorted { lhs, rhs in
                (statusRank(lhs.status), lhs.name) < (statusRank(rhs.status), rhs.name)
            }
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Picker(AgentsL10n.text("list.view", "View"), selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 420)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    switch mode {
                    case .gallery:
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(agents) { agent in
                                NavigationLink(value: AgentRoute(id: agent.id)) {
                                    AgentCard(agent: agent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    case .org:
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(org.isEmpty ? OrgNode.tree(from: app.agents) : org) { node in
                                OrgTreeRow(node: node, depth: 0)
                            }
                        }
                        .padding(12)
                        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    }

                    if app.agents.isEmpty {
                        ContentUnavailableView(AgentsL10n.text("list.empty", "No agents yet"), systemImage: "person.3", description: Text(AgentsL10n.text("list.empty_help", "Hire your first agent in the web app.")))
                    }
                }
                .padding(16)
            }
            .readableWidth(1100)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(AgentsL10n.text("list.title", "Agents"))
            .paperclipDestinations()
            .refreshable { await reload() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Toggle(AgentsL10n.text("list.show_terminated", "Show terminated agents"), isOn: $showTerminated)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { hiring = true } label: { Image(systemName: "person.badge.plus") }
                        .accessibilityLabel(AgentsL10n.text("hire.title", "Hire agent"))
                }
            }
            .task(id: app.revision) { await reload() }
            .autoRefresh(every: .seconds(8)) { await app.reloadAgents() }
            .sheet(isPresented: $hiring) {
                HireAgentSheet { agent in path.append(AgentRoute(id: agent.id)) }
            }
        }
    }

    private func statusRank(_ status: AgentStatus) -> Int {
        switch status {
        case .error: return 0
        case .running: return 1
        case .pendingApproval: return 2
        case .active, .idle: return 3
        case .paused: return 4
        default: return 5
        }
    }

    private func reload() async {
        await app.reloadAgents()
        await reloadOrg()
    }

    private func reloadOrg() async {
        guard let client = app.client, let companyId = app.selectedCompanyId else { return }
        org = (try? await client.orgChart(companyId: companyId)) ?? []
    }
}

struct AgentCard: View {
    let agent: Agent

    var body: some View {
        let (a, b) = AgentPalette.colors(for: agent)
        VStack(spacing: 10) {
            AgentAvatar(agent: agent, size: 84)
                .shadow(color: b.opacity(0.35), radius: 12, y: 6)
                .padding(.top, 10)
            VStack(spacing: 3) {
                Text(agent.name).font(.headline).lineLimit(1)
                Text(agent.title ?? agent.roleLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            StatusPill(status: agent.status)
            Text(agent.modelName ?? agent.adapterLabel)
                .font(.caption2.weight(.medium).monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .background {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .overlay(alignment: .top) {
                    LinearGradient(colors: [a.opacity(0.28), b.opacity(0.12), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 110)
                        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous))
                }
        }
        .overlay {
            if agent.status == .error {
                RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color.red.opacity(0.5), lineWidth: 1.5)
            }
        }
        .opacity(agent.status == .terminated ? 0.5 : 1)
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Agent status as a small pill; the dot pulses while the agent is running.
struct StatusPill: View {
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status == .running ? "bolt.fill" : "circle.fill")
                .font(.system(size: status == .running ? 9 : 6))
                .symbolEffect(.pulse, isActive: status == .running)
            Text(status.label)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(status.tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(status.tint.opacity(0.13), in: Capsule())
    }
}

struct OrgTreeRow: View {
    @Environment(AppModel.self) private var app
    let node: OrgNode
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: AgentRoute(id: node.id)) {
                HStack(spacing: 10) {
                    if depth > 0 {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    AgentAvatar(agent: app.agent(node.id), size: 34)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(node.name).font(.subheadline.weight(.semibold))
                        Text(node.title ?? app.agent(node.id)?.title ?? AgentRole.label(for: node.role ?? ""))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let status = app.agent(node.id)?.status ?? node.status {
                        Circle().fill(status.tint).frame(width: 8, height: 8)
                    }
                }
                .padding(.vertical, 6)
                .padding(.leading, CGFloat(depth) * 18)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ForEach(node.reports) { child in
                OrgTreeRow(node: child, depth: depth + 1)
            }
        }
    }
}
