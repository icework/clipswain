import XCTest
@testable import PaperclipKit

final class TaskTimingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1000)
    func run(_ json: String) throws -> IssueRun {
        try PaperclipJSON.decoder.decode(IssueRun.self, from: Data(json.utf8))
    }
    func testTerminalStopsAndReopenedIgnoresOldCompletion() {
        var issue = Issue(id: "i", companyId: "c", title: "Test", status: .done, priority: .medium)
        issue.createdAt = Date(timeIntervalSince1970: 100)
        issue.completedAt = Date(timeIntervalSince1970: 400)
        XCTAssertEqual(TaskTiming.elapsed(issue, at: now), 300)
        issue.status = .inProgress
        XCTAssertEqual(TaskTiming.elapsed(issue, at: now), 900)
        issue.status = .cancelled
        XCTAssertNil(TaskTiming.elapsed(issue, at: now))
        issue.cancelledAt = Date(timeIntervalSince1970: 700)
        XCTAssertEqual(TaskTiming.elapsed(issue, at: now), 600)
    }
    func testQueueUnknownAndIncompleteNeverAccumulateExecution() {
        let start = Date(timeIntervalSince1970: 100)
        XCTAssertNil(TaskTiming.runDuration(status: "queued", start: start, finish: nil, now: now))
        XCTAssertNil(TaskTiming.runDuration(status: "succeeded", start: start, finish: nil, now: now))
        XCTAssertNil(TaskTiming.runDuration(status: "future_status", start: start, finish: nil, now: now))
        XCTAssertNil(TaskTiming.runDuration(status: "running", start: nil, finish: nil, now: now))
        XCTAssertEqual(TaskTiming.runDuration(status: "running", start: start, finish: nil, now: now), 900)
        XCTAssertEqual(TaskTiming.runDuration(status: "running", start: start, finish: now, now: now.addingTimeInterval(500)), 900)
        XCTAssertNil(TaskTiming.interval(from: now, to: start))
    }
    func testDeduplicationParallelRunsAndRetries() throws {
        let first = try run(#"{"runId":"a","status":"succeeded","startedAt":"1970-01-01T00:01:40Z","finishedAt":"1970-01-01T00:03:20Z"}"#)
        let retry = try run(#"{"runId":"b","status":"failed","startedAt":"1970-01-01T00:02:00Z","finishedAt":"1970-01-01T00:03:00Z","retryOfRunId":"a"}"#)
        let queue = try run(#"{"runId":"q","status":"queued"}"#)
        XCTAssertEqual(TaskTiming.cumulative([first, first, retry, queue], at: now), 160)
        XCTAssertEqual(TaskTiming.uniqueRuns([first, first, retry]).count, 2)
        let incomplete = try run(#"{"runId":"missing","status":"failed","finishedAt":"1970-01-01T00:03:00Z"}"#)
        XCTAssertNil(TaskTiming.cumulative([first, incomplete], at: now))
    }
    func testRealStatusShapesAndEchoedPatch() throws {
        func change(_ details: String) throws -> IssueActivity {
            try PaperclipJSON.decoder.decode(IssueActivity.self, from: Data("{\"id\":\"e\",\"action\":\"issue.updated\",\"createdAt\":\"2026-10-21T05:04:17.301Z\",\"details\":\(details)}".utf8))
        }
        let explicit = try change(#"{"changes":{"status":{"from":"in_progress","to":"blocked"}},"status":"blocked"}"#)
        XCTAssertEqual(explicit.statusChange?.from, .inProgress)
        XCTAssertEqual(explicit.statusChange?.to, .blocked)
        XCTAssertEqual(try change(#"{"_previous":{"status":"todo"},"status":"in_progress"}"#).statusChange?.to, .inProgress)
        XCTAssertEqual(try change(#"{"reopenedFrom":"blocked","status":"todo"}"#).statusChange?.from, .blocked)
        XCTAssertNil(try change(#"{"changes":{},"status":"todo"}"#).statusChange)
        XCTAssertNil(try change(#"{"_previous":{"status":"todo"},"status":"todo"}"#).statusChange)
        XCTAssertNil(try change(#"{"_previous":{"status":"new_status"},"status":"todo"}"#).statusChange)
    }
    func testDurationFormattingDoesNotInventZeros() {
        XCTAssertEqual(TaskTiming.text(nil, locale: Locale(identifier: "zh-Hans")), "时间记录不完整")
        XCTAssertEqual(TaskTiming.text(-10, locale: Locale(identifier: "zh-Hans")), "时间记录不完整")
        XCTAssertEqual(TaskTiming.text(.infinity, locale: Locale(identifier: "zh-Hans")), "时间记录不完整")
        XCTAssertEqual(TaskTiming.text(0, locale: Locale(identifier: "zh-Hans")), "0秒")
        XCTAssertEqual(TaskTiming.text(0.4, locale: Locale(identifier: "zh-Hans")), "不足1秒")
        XCTAssertEqual(TaskTiming.text(193, locale: Locale(identifier: "zh-Hans")), "3分钟13秒")
        XCTAssertEqual(TaskTiming.text(3669, locale: Locale(identifier: "zh-Hans")), "1小时1分钟")
        XCTAssertEqual(TaskTiming.text(90000, locale: Locale(identifier: "zh-Hans")), "1天1小时")
    }
}
