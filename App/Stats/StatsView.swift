import Charts
import PaperclipKit
import SwiftUI

struct StatsView: View {
    @Environment(AppModel.self) private var app
    private struct Dataset {
        let companyId: String
        let dashboard: DashboardSummary
        let issues: [Issue]
        let agents: [Agent]
        let updatedAt: Date
    }
    @State private var data: Dataset?
    @State private var error: String?
    @State private var loading = false
    @State private var loadID = UUID()
    @State private var range = StatsRange.twoWeeks
    @State private var scope = StatsScope.main

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let error { ErrorBanner(message: error) { Task { await load() } } }
                if let data, data.companyId == app.selectedCompanyId {
                    let stats = CompanyStats(issues: data.issues, agents: data.agents, range: range,
                                             scope: scope, now: data.updatedAt)
                    VStack(alignment: .leading, spacing: 10) {
                        Picker(AppL10n.text("stats.time_range", "Time range"), selection: $range) {
                            ForEach(StatsRange.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented)
                        Picker(AppL10n.text("stats.task_scope", "Task scope"), selection: $scope) {
                            ForEach(StatsScope.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented)
                        Text(scope == .main ? AppL10n.text("stats.main_scope_help", "Main tasks show final deliveries without counting their subtasks again.") : AppL10n.text("stats.all_scope_help", "Includes main tasks and subtasks to show all task records."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    DeliveryCard(stats: stats)
                    TaskFlowCard(stats: stats)
                    CycleTimeCard(stats: stats)
                    ContributionCard(stats: stats)
                    Text(AppL10n.text("stats.company_scope", "Company runs and costs · Independent of task scope"))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    RunActivityCard(stats: RunStatistics(activity: data.dashboard.runActivity, range: range, now: data.updatedAt))
                    SpendCard(costs: data.dashboard.costs, agents: data.agents)
                    Text(AppL10n.text("stats.updated_at", "Updated \(AppL10n.date(data.updatedAt, style: .dateTime.year().month().day().hour().minute()))"))
                        .font(.caption2).foregroundStyle(.secondary)
                } else if !loading && error == nil {
                    ContentUnavailableView(AppL10n.text("stats.no_data", "No statistics available"), systemImage: "chart.bar.xaxis")
                }
            }
            .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 28)
        }
        .readableWidth()
        .background(Color(.systemGroupedBackground))
        .navigationTitle(AppL10n.text("stats.title", "Statistics"))
        .refreshable { await load() }
        .overlay { if loading && data == nil { ProgressView() } }
        .task(id: "\(app.selectedCompanyId ?? "")-\(app.revision)") { await load() }
        .autoRefresh(every: .seconds(60)) { await load() }
    }

    private func load() async {
        guard let client = app.client, let companyId = app.selectedCompanyId else {
            data = nil
            return
        }
        let request = UUID()
        loadID = request
        if data?.companyId != companyId { data = nil; error = nil }
        loading = true
        defer { if loadID == request { loading = false } }
        do {
            async let summary = client.dashboard(companyId: companyId)
            async let issues = client.issues(companyId: companyId)
            async let agents = client.agents(companyId: companyId)
            let values = try await (summary, issues, agents)
            guard loadID == request, !Task.isCancelled, app.client === client,
                  app.selectedCompanyId == companyId else { return }
            data = Dataset(companyId: companyId, dashboard: values.0, issues: values.1,
                           agents: values.2, updatedAt: .now)
            error = nil
        } catch {
            guard loadID == request, !Task.isCancelled, app.selectedCompanyId == companyId else { return }
            self.error = (data == nil ? AppL10n.text("stats.load_failed", "Could not load statistics: ") : AppL10n.text("stats.refresh_failed", "Refresh failed. Showing the last complete data: ")) + error.localizedDescription
        }
    }
}

private struct StatsCardHeader: View {
    let title: String
    let symbol: String
    let tint: Color
    var body: some View {
        Label {
            Text(title).font(.headline)
        } icon: {
            Image(systemName: symbol).font(.footnote.weight(.bold)).foregroundStyle(tint)
        }
    }
}

private struct StatsMetrics: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let values: [(String, String)]
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            ForEach(values.indices, id: \.self) { index in
                VStack(alignment: .leading, spacing: 4) {
                    Text(values[index].0).font(.title3.weight(.bold).monospacedDigit())
                    Text(values[index].1).font(.caption).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct DeliveryCard: View {
    let stats: CompanyStats
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatsCardHeader(title: AppL10n.text("stats.delivery_review", "Delivery review"), symbol: "checkmark.seal", tint: .green)
            Text("\(AppL10n.date(stats.start, style: .dateTime.month().day())) – \(AppL10n.date(stats.now, style: .dateTime.month().day())) · \(stats.scope.label)")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(stats.completed.count.formatted(.number.locale(AppL10n.locale))).font(.system(.largeTitle, design: .rounded).weight(.bold)).monospacedDigit()
                Text(AppL10n.text("stats.completed_suffix", "completed")).font(.headline).foregroundStyle(.secondary)
            }
            let delta = stats.completed.count - stats.previousCompleted
            let change = delta == 0 ? AppL10n.text("stats.unchanged", "No change") : delta > 0 ? AppL10n.text("stats.increase", "Up by \(delta) tasks") : AppL10n.text("stats.decrease", "Down by \(-delta) tasks")
            Text(AppL10n.text("stats.previous_comparison", "Previous period: \(stats.previousCompleted) tasks · \(change)"))
                .font(.subheadline)
            if stats.scope == .main {
                Text(AppL10n.text("stats.subtasks_excluded", "Another \(stats.completedSubtasks) subtasks were completed in this period, excluded from the total above."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(AppL10n.text("stats.period_help", "Compared with the corresponding time \(stats.range.days) days earlier. Uses the latest completion time of currently completed tasks; reopened tasks are excluded."))
                .font(.caption).foregroundStyle(.secondary)
            if stats.missingCompletionDates > 0 {
                Text(AppL10n.text("stats.missing_completion_dates", "\(stats.missingCompletionDates) other completed tasks have no completion date and cannot be assigned to a period."))
                    .font(.caption).foregroundStyle(.orange)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
}

private struct TaskFlowCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let stats: CompanyStats
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatsCardHeader(title: AppL10n.text("stats.delivery_trend", "Delivery trend"), symbol: "chart.bar.xaxis", tint: .teal)
            StatsMetrics(values: [(stats.created.formatted(.number.locale(AppL10n.locale)), AppL10n.text("stats.created_period", "Created this period")), (stats.completed.count.formatted(.number.locale(AppL10n.locale)), AppL10n.text("stats.completed_period", "Completed this period"))])
            if stats.created == 0 && stats.completed.isEmpty {
                Text(AppL10n.text("stats.empty_period", "No tasks were created or completed in this period.")).font(.footnote).foregroundStyle(.secondary)
            } else {
                Chart(stats.flow) { point in
                    BarMark(x: .value(AppL10n.text("stats.date", "Date"), point.date, unit: .day), y: .value(AppL10n.text("stats.task_count", "Tasks"), point.count))
                        .foregroundStyle(by: .value(AppL10n.text("stats.record", "Record"), point.kind.label))
                        .position(by: .value(AppL10n.text("stats.record", "Record"), point.kind.label))
                        .cornerRadius(2)
                }
                .chartForegroundStyleScale([CompanyStats.FlowKind.created.label: Color.blue, CompanyStats.FlowKind.completed.label: Color.green])
                .chartXScale(domain: stats.domain)
                .chartXAxis { AxisMarks(values: .stride(by: .day, count: typeSize.isAccessibilitySize ? (stats.range == .week ? 3 : 7) : (stats.range == .week ? 1 : 2))) {
                    AxisValueLabel(format: .dateTime.month(.defaultDigits).day())
                } }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                .chartLegend(position: .bottom).frame(height: typeSize.isAccessibilitySize ? 240 : 180)
            }
            Text(AppL10n.text("stats.flow_help", "Grouped by local date, using each task’s creation and most recent completion time."))
                .font(.caption).foregroundStyle(.secondary)
        }.card()
    }
}

private struct CycleTimeCard: View {
    let stats: CompanyStats
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatsCardHeader(title: AppL10n.text("stats.cycle_time", "Time to completion"), symbol: "timer", tint: .orange)
            if let median = stats.median {
                StatsMetrics(values: [(TaskTiming.text(median), AppL10n.text("stats.median", "Typical duration · Median")),
                                      (stats.p90.map(TaskTiming.text) ?? "—", AppL10n.text("stats.p90", "90% of tasks finish within this time"))])
                Text(AppL10n.text("stats.valid_samples", "Valid samples: \(stats.timed.count)/\(stats.completed.count). Creation to completion, including queues, blockers, and waiting."))
                    .font(.caption).foregroundStyle(.secondary)
                if let previous = stats.previousMedian {
                    Text(AppL10n.text("stats.previous_median", "Previous-period median: \(TaskTiming.text(previous))")).font(.footnote).foregroundStyle(.secondary)
                }
                if stats.p90 == nil {
                    Text(AppL10n.text("stats.p90_insufficient", "P90 is shown only with at least 10 valid samples.")).font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                Text(AppL10n.text("stats.long_tasks", "Tasks with longer durations")).font(.subheadline.weight(.semibold))
                ForEach(stats.timed.prefix(3)) { item in
                    NavigationLink(value: IssueRoute(id: item.id)) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.issue.title).font(.subheadline).foregroundStyle(.primary).lineLimit(2)
                            Text("\(item.issue.displayKey) · \(TaskTiming.text(item.duration))")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            } else {
                Text(stats.completed.isEmpty ? AppL10n.text("stats.no_completions", "No tasks have been completed in this period.") : AppL10n.text("stats.no_valid_dates", "Completed tasks are missing valid start or end dates, so duration statistics are unavailable."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.card()
    }
}

private struct ContributionCard: View {
    let stats: CompanyStats
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatsCardHeader(title: AppL10n.text("stats.distribution", "Delivery distribution"), symbol: "person.3", tint: .indigo)
            if stats.contributions.isEmpty {
                Text(AppL10n.text("stats.empty_distribution", "No deliveries with an available owner in this period.")).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(stats.contributions) { contribution in
                if let agent = contribution.agent {
                    NavigationLink(value: AgentRoute(id: agent.id)) { row(contribution) }.buttonStyle(.plain)
                } else { row(contribution) }
            }
            Text(AppL10n.text("stats.distribution_help", "Grouped by each task’s current assignee. Agents whose profiles are unavailable are hidden; their tasks still count toward delivery totals and durations."))
                .font(.caption).foregroundStyle(.secondary)
        }.card()
    }
    private func row(_ contribution: CompanyStats.Contribution) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if let agent = contribution.agent { AgentAvatar(agent: agent, size: 30) }
            VStack(alignment: .leading, spacing: 4) {
                Text(contribution.name).font(.subheadline.weight(.semibold))
                let median = contribution.median.map(TaskTiming.text) ?? AppL10n.text("common.not_recorded", "Not recorded")
                Text(AppL10n.text("stats.owner_summary", "\(contribution.count) completed · Median duration \(median)"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RunActivityCard: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let stats: RunStatistics
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatsCardHeader(title: AppL10n.text("stats.reliability", "Run reliability"), symbol: "waveform.path.ecg", tint: .blue)
            if !stats.supplied || stats.days.isEmpty {
                Text(AppL10n.text("stats.no_run_data", "The server did not provide run summaries for this period.")).font(.footnote).foregroundStyle(.secondary)
            } else {
                StatsMetrics(values: [(stats.succeeded.formatted(.number.locale(AppL10n.locale)), AppL10n.text("stats.run_succeeded", "Succeeded")), (stats.recovered.formatted(.number.locale(AppL10n.locale)), AppL10n.text("stats.run_recovered", "Recovered by retry")), (stats.failed.formatted(.number.locale(AppL10n.locale)), AppL10n.text("stats.run_failed", "Unrecovered failures"))])
                if stats.total > 0 {
                    Chart(stats.segments) { segment in
                        BarMark(x: .value(AppL10n.text("stats.utc_date", "UTC date"), segment.date, unit: .day, calendar: RunStatistics.calendar), y: .value(AppL10n.text("stats.run_count", "Runs"), segment.count))
                            .foregroundStyle(by: .value(AppL10n.text("stats.outcome", "Outcome"), segment.kind.label)).cornerRadius(2)
                    }
                    .chartForegroundStyleScale([RunStatistics.Kind.succeeded.label: Color.green, RunStatistics.Kind.recovered.label: Color.orange,
                                                RunStatistics.Kind.failed.label: Color.red, RunStatistics.Kind.other.label: Color.gray])
                    .chartXScale(domain: stats.domain)
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: typeSize.isAccessibilitySize ? (stats.requestedDays == 7 ? 3 : 7) : (stats.requestedDays == 7 ? 1 : 2), calendar: RunStatistics.calendar)) { value in
                        AxisValueLabel {
                            if let date = value.as(Date.self) { Text(RunStatistics.dayLabel(date)) }
                        }
                    } }
                    .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) }
                    .chartLegend(position: .bottom).frame(height: typeSize.isAccessibilitySize ? 240 : 180)
                    .environment(\.calendar, RunStatistics.calendar)
                    .environment(\.timeZone, RunStatistics.calendar.timeZone)
                } else {
                    Text(AppL10n.text("stats.no_runs", "No runs were recorded on the reported dates.")).font(.footnote).foregroundStyle(.secondary)
                }
                Text(AppL10n.text("stats.run_summary", "\(stats.total) run records, by UTC date including today. Recovered runs failed before a later retry succeeded. A successful run does not mean the task is complete."))
                    .font(.caption).foregroundStyle(.secondary)
                if stats.days.count < stats.requestedDays {
                    Text(AppL10n.text("stats.run_coverage", "Data is available for \(stats.days.count)/\(stats.requestedDays) days. Missing dates are not counted as zero."))
                        .font(.caption).foregroundStyle(.orange)
                }
                if !stats.failureReasons.isEmpty {
                    Divider()
                    Text(AppL10n.text("stats.failure_reasons", "Top reasons for unrecovered failures")).font(.subheadline.weight(.semibold))
                    ForEach(stats.failureReasons.prefix(4), id: \.code) { reason in
                        HStack(alignment: .top) {
                            Text(reason.code).font(.caption.monospaced()).textSelection(.enabled)
                            Spacer(minLength: 8)
                            Text(AppL10n.text("stats.reason_count", "\(reason.count) runs")).font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        }.card()
    }
}

private struct SpendCard: View {
    let costs: DashboardSummary.Costs
    let agents: [Agent]
    private var spend: [Agent] { agents.filter { ($0.spentMonthlyCents ?? 0) > 0 }.sorted { ($0.spentMonthlyCents ?? 0) > ($1.spentMonthlyCents ?? 0) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            StatsCardHeader(title: AppL10n.text("stats.monthly_costs", "Recorded costs this month"), symbol: "dollarsign.circle", tint: .mint)
            Text(costs.monthSpendCents.dollars).font(.largeTitle.weight(.bold).monospacedDigit())
            if costs.monthBudgetCents > 0 {
                ProgressView(value: min(Double(costs.monthSpendCents) / Double(costs.monthBudgetCents), 1))
                Text(AppL10n.text("stats.budget_remaining", "Monthly budget \(costs.monthBudgetCents.dollars) · Remaining \(max(0, costs.monthBudgetCents - costs.monthSpendCents).dollars)"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(spend.prefix(6)) { agent in
                HStack(alignment: .top) {
                    Text(agent.name).font(.subheadline)
                    Spacer(minLength: 8)
                    Text((agent.spentMonthlyCents ?? 0).dollars).font(.subheadline.monospacedDigit())
                }
            }
            Text(AppL10n.text("stats.cost_help", "Uses the server’s UTC calendar month, independently of the selected period. Only reported costs are included. Subscription usage and unreported costs may be excluded, so $0 does not mean no cost."))
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).card()
    }
}
