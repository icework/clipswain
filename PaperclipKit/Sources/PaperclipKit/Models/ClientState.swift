import Foundation

/// Accumulates a run's NDJSON transcript slice by slice. Content and the read offset advance
/// together, so a failed page never leaves already-appended content behind an old offset.
public struct RunLogCursor: Sendable, Equatable {
    public private(set) var content = ""
    public private(set) var offset = 0

    public init() {}

    /// Applies one slice read at the current offset. Returns whether more is available now.
    @discardableResult
    public mutating func apply(_ slice: HeartbeatRunLog) -> Bool {
        content += slice.content
        if let next = slice.nextOffset {
            offset = next
            return true
        }
        offset += slice.content.utf8.count
        return false
    }

    public var chunks: [HeartbeatRunLog.Chunk] { HeartbeatRunLog(content: content).chunks }
}

/// Which attention items the user already knows about, newest last, bounded in size.
public struct NotificationLedger: Sendable, Equatable {
    public private(set) var ids: [String]
    public let capacity: Int

    public init(ids: [String] = [], capacity: Int = 500) {
        self.ids = ids
        self.capacity = capacity
    }

    public func unseen(_ candidates: [String]) -> [String] {
        let known = Set(ids)
        return candidates.filter { !known.contains($0) }
    }

    /// Records ids as known (seen on screen or delivered), dropping the oldest past capacity.
    public mutating func record(_ newIds: [String]) {
        let known = Set(ids)
        ids.append(contentsOf: newIds.filter { !known.contains($0) })
        if ids.count > capacity { ids.removeFirst(ids.count - capacity) }
    }
}

/// Decides how browser sign-in polling continues after each check: back off on errors,
/// and stop once the challenge is gone, expired, or the server keeps failing.
public struct SignInPollPolicy: Sendable, Equatable {
    public enum Decision: Equatable, Sendable {
        case retry(after: Double)
        case stop(Reason)
    }

    public enum Reason: Equatable, Sendable {
        case expired
        case notFound
        case tooManyFailures
    }

    public var baseInterval: Double
    public var maxInterval: Double
    public var maxConsecutiveFailures: Int
    public private(set) var consecutiveFailures = 0

    public init(baseInterval: Double = 1.5, maxInterval: Double = 15, maxConsecutiveFailures: Int = 8) {
        self.baseInterval = max(baseInterval, 1)
        self.maxInterval = maxInterval
        self.maxConsecutiveFailures = maxConsecutiveFailures
    }

    /// Call after a check that returned a non-final state.
    public mutating func afterPending(now: Date, expiresAt: Date?) -> Decision {
        consecutiveFailures = 0
        if let expiresAt, now >= expiresAt { return .stop(.expired) }
        return .retry(after: baseInterval)
    }

    /// Call after a check that threw. A 404 means the challenge no longer exists.
    public mutating func afterError(status: Int?, now: Date, expiresAt: Date?) -> Decision {
        if status == 404 { return .stop(.notFound) }
        if let expiresAt, now >= expiresAt { return .stop(.expired) }
        consecutiveFailures += 1
        if consecutiveFailures >= maxConsecutiveFailures { return .stop(.tooManyFailures) }
        let delay = baseInterval * pow(2, Double(consecutiveFailures))
        return .retry(after: min(delay, maxInterval))
    }
}
