import XCTest
@testable import Clipswain

@MainActor
final class AppIdentityTests: XCTestCase {
    func testInstalledAppMetadataMatchesClipswainRoutesAndBackgroundTask() {
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Clipswain")
        let types = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        let schemes = types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
        XCTAssertEqual(schemes, ["clipswain"])
        let identifiers = Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers") as? [String] ?? []
        XCTAssertEqual(identifiers, [AttentionNotifier.taskIdentifier])
    }

    func testClipswainDeepLinksDoNotClaimTheOriginalAppsScheme() {
        let app = AppModel()
        app.open(URL(string: "clipswain://issue/demo-task")!)
        guard case .issue("demo-task")? = app.pendingRoute else { return XCTFail("Expected task route") }
        app.pendingRoute = nil
        app.open(URL(string: "clipswain://approval/demo-approval")!)
        guard case .approval("demo-approval")? = app.pendingRoute else { return XCTFail("Expected approval route") }
        app.pendingRoute = nil
        app.open(URL(string: "paperclip://issue/demo-task")!)
        XCTAssertNil(app.pendingRoute)
    }
}
