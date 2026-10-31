import XCTest
@testable import PaperclipKit

final class SignInPollPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000)

    func testPendingKeepsBaseInterval() {
        var policy = SignInPollPolicy(baseInterval: 1.5)
        XCTAssertEqual(policy.afterPending(now: now, expiresAt: now.addingTimeInterval(60)), .retry(after: 1.5))
    }

    func testErrorsBackOffAndCap() {
        var policy = SignInPollPolicy(baseInterval: 1, maxInterval: 5, maxConsecutiveFailures: 10)
        let delays = (0..<4).map { _ in policy.afterError(status: 500, now: now, expiresAt: nil) }
        XCTAssertEqual(delays, [.retry(after: 2), .retry(after: 4), .retry(after: 5), .retry(after: 5)])
    }

    func testSuccessResetsBackoff() {
        var policy = SignInPollPolicy(baseInterval: 1)
        _ = policy.afterError(status: 429, now: now, expiresAt: nil)
        _ = policy.afterPending(now: now, expiresAt: nil)
        XCTAssertEqual(policy.afterError(status: 429, now: now, expiresAt: nil), .retry(after: 2))
    }

    func testStopsWhenGoneExpiredOrFailingRepeatedly() {
        var policy = SignInPollPolicy(maxConsecutiveFailures: 3)
        XCTAssertEqual(policy.afterError(status: 404, now: now, expiresAt: nil), .stop(.notFound))
        XCTAssertEqual(policy.afterPending(now: now, expiresAt: now), .stop(.expired))
        XCTAssertEqual(policy.afterError(status: nil, now: now.addingTimeInterval(5), expiresAt: now), .stop(.expired))
        _ = policy.afterError(status: 500, now: now, expiresAt: nil)
        _ = policy.afterError(status: 500, now: now, expiresAt: nil)
        XCTAssertEqual(policy.afterError(status: 500, now: now, expiresAt: nil), .stop(.tooManyFailures))
    }
}
