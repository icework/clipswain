import PaperclipKit
import SwiftUI

/// One heartbeat run: lifecycle events and the agent's raw output, streamed while it runs.
struct RunDetailView: View {
    @Environment(AppModel.self) private var app
    let runId: String

    @State private var run: HeartbeatRun?
    @State private var events: [HeartbeatRunEvent] = []
    @State private var chunks: [HeartbeatRunLog.Chunk] = []
    @State private var log = RunLogCursor()
    @State private var section = Section.output
    @State private var loadError: String?
    @State private var runner = ActionRunner()

    enum Section: String, CaseIterable, Identifiable {
        case output, events
        var id: String { rawValue }
        var label: String { self == .output ? AgentsL10n.text("run.output", "Output") : AgentsL10n.text("run.events", "Events") }
    }

    private var isLive: Bool { run?.status == "running" || run?.status == "queued" }

    var body: some View {
        VStack(spacing: 0) {
            if let run {
                header(run)
            }
            Picker(AgentsL10n.text("run.content", "Content"), selection: $section) {
                ForEach(Section.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let loadError {
                ErrorBanner(message: loadError) { Task { await load() } }.padding()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        switch section {
                        case .output:
                            if chunks.isEmpty {
                                Text(isLive ? AgentsL10n.text("run.waiting_output", "Waiting for output…") : AgentsL10n.text("run.no_output", "This run has no output."))
                                    .foregroundStyle(.secondary)
                                    .padding()
                            }
                            ForEach(Array(chunks.enumerated()), id: \.offset) { _, chunk in
                                Text(chunk.text.trimmingCharacters(in: .newlines))
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(chunk.stream == "stderr" ? Color.red : Color.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        case .events:
                            ForEach(events) { event in
                                EventRow(event: event)
                            }
                        }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal)
                }
                .background(Color(.secondarySystemBackground))
                .onChange(of: chunks.count) { if isLive { proxy.scrollTo("end") } }
                .onChange(of: events.count) { if isLive { proxy.scrollTo("end") } }
            }
        }
        .navigationTitle(AgentsL10n.text("run.detail", "Run details"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isLive {
                ToolbarItem(placement: .primaryAction) {
                    Button(AgentsL10n.text("action.stop", "Stop"), role: .destructive) { Task { await cancel() } }
                        .disabled(runner.isBusy)
                }
            }
        }
        .task { await load() }
        .autoRefresh(every: isLive ? .seconds(3) : .seconds(60)) { await load() }
        .errorAlert(runner)
    }

    private func header(_ run: HeartbeatRun) -> some View {
        HStack(spacing: 10) {
            AgentAvatar(agent: app.agent(run.agentId), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                RunRow(run: run)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    /// Fetches only what is new: events after the last seq and log bytes after the last offset.
    private func load() async {
        guard let client = app.client else { return }
        do {
            run = try await client.run(id: runId)
            let newEvents = try await client.runEvents(runId: runId, afterSeq: events.last?.seq ?? 0)
            events.append(contentsOf: newEvents.filter { event in !events.contains { $0.id == event.id } })
            // Each slice advances content and offset together, so a failed page is simply
            // re-read from the same offset on the next poll.
            for _ in 0..<20 {
                let slice = try await client.runLog(runId: runId, offset: log.offset)
                let more = log.apply(slice)
                chunks = log.chunks
                if !more { break }
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func cancel() async {
        guard let client = app.client else { return }
        await runner.run {
            try await client.cancelRun(id: runId)
            await load()
        }
    }
}

private struct EventRow: View {
    let event: HeartbeatRunEvent

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.message ?? event.eventType)
                    .font(.footnote)
                HStack(spacing: 6) {
                    Text(event.eventType)
                    if let date = event.createdAt {
                        Text(AppL10n.date(date, style: .dateTime.hour().minute().second()))
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var tint: Color {
        switch event.level {
        case "error": return .red
        case "warn", "warning": return .orange
        default: return .secondary
        }
    }
}
