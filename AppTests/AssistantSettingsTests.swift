import XCTest
import PaperclipKit
@testable import Clipswain

@MainActor
final class AssistantSettingsTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    private let configKey = "paperclip.assistant.provider"
    private let migrationKey = "paperclip.assistant.scopedKeysMigrated"

    override func setUp() {
        super.setUp()
        suite = "PaperclipTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func save(_ config: LLMProviderConfig) throws {
        defaults.set(try JSONEncoder().encode(config), forKey: configKey)
    }

    func testLegacyMigrationPreservesModelAndRemovesOldSecret() throws {
        try save(.init(kind: .openAICompatible, baseURL: "https://opencode.ai/zen/go/v1", model: "kimi-k3"))
        let keys = MemoryKeys(["default": "old-go-key"])
        let settings = AssistantSettings(defaults: defaults, keyStore: keys)
        XCTAssertEqual(settings.config.kind, .openCodeGo)
        XCTAssertEqual(settings.config.model, "kimi-k3")
        XCTAssertEqual(settings.apiKey, "old-go-key")
        XCTAssertEqual(keys.values["opencode_go"], "old-go-key")
        XCTAssertNil(keys.values["default"])
        XCTAssertTrue(defaults.bool(forKey: migrationKey))
    }

    func testFailedMigrationRetriesOriginalOwnerAfterSwitchingServices() throws {
        try save(.init(kind: .openCodeGo, model: "kimi-k3"))
        let keys = MemoryKeys(["default": "go-secret"])
        keys.failWrites = true
        let first = AssistantSettings(defaults: defaults, keyStore: keys)
        XCTAssertNotNil(first.credentialError)
        XCTAssertFalse(defaults.bool(forKey: migrationKey))
        XCTAssertEqual(keys.values["default"], "go-secret")
        first.selectProvider(.openRouter)
        keys.failWrites = false
        let next = AssistantSettings(defaults: defaults, keyStore: keys)
        XCTAssertEqual(next.config.kind, .openRouter)
        XCTAssertEqual(next.apiKey, "")
        XCTAssertNil(keys.values["openrouter"])
        XCTAssertEqual(keys.values["opencode_go"], "go-secret")
        XCTAssertNil(keys.values["default"])
    }

    func testLockedKeychainDoesNotMarkMigrationCompleteOrWriteAnything() throws {
        try save(.init(kind: .openCodeGo, model: "kimi-k3"))
        let keys = MemoryKeys(["default": "go-secret"])
        keys.failReads = true
        let settings = AssistantSettings(defaults: defaults, keyStore: keys)
        XCTAssertNotNil(settings.credentialError)
        XCTAssertFalse(defaults.bool(forKey: migrationKey))
        XCTAssertEqual(keys.writeCount, 0)
        keys.failReads = false
        XCTAssertEqual(AssistantSettings(defaults: defaults, keyStore: keys).apiKey, "go-secret")
    }

    func testProviderSwitchRestoresSeparateModelsAndKeysWithoutWritingKeys() throws {
        defaults.set(true, forKey: migrationKey)
        try save(.init(kind: .openCodeGo, model: "kimi-k3"))
        let keys = MemoryKeys(["opencode_go": "go-secret", "openrouter": "router-secret"])
        let settings = AssistantSettings(defaults: defaults, keyStore: keys)
        settings.selectProvider(.openRouter)
        XCTAssertEqual(settings.apiKey, "router-secret")
        settings.config.model = "vendor/router-model"
        settings.selectProvider(.openCodeGo)
        XCTAssertEqual(settings.apiKey, "go-secret")
        XCTAssertEqual(settings.config.model, "kimi-k3")
        settings.selectProvider(.openRouter)
        XCTAssertEqual(settings.config.model, "vendor/router-model")
        XCTAssertEqual(keys.writeCount, 0)
        let relaunched = AssistantSettings(defaults: defaults, keyStore: keys)
        XCTAssertEqual(relaunched.apiKey, "router-secret")
    }

    func testReadFailureOnSwitchDoesNotDeleteCredential() throws {
        defaults.set(true, forKey: migrationKey)
        try save(.init(kind: .openCodeGo, model: "kimi-k3"))
        let keys = MemoryKeys(["opencode_go": "go-secret", "openrouter": "router-secret"])
        let settings = AssistantSettings(defaults: defaults, keyStore: keys)
        keys.failReads = true
        settings.selectProvider(.openRouter)
        XCTAssertEqual(settings.apiKey, "")
        XCTAssertNotNil(settings.credentialError)
        XCTAssertEqual(keys.values["openrouter"], "router-secret")
        XCTAssertEqual(keys.writeCount, 0)
    }

    func testResetOnlyClearsCurrentServiceAndKeepsStateWhenDeleteFails() throws {
        defaults.set(true, forKey: migrationKey)
        try save(.init(kind: .openCodeGo, model: "kimi-k3"))
        let keys = MemoryKeys(["opencode_go": "go-secret", "openrouter": "router-secret"])
        let settings = AssistantSettings(defaults: defaults, keyStore: keys)
        keys.failWrites = true
        settings.reset()
        XCTAssertEqual(settings.apiKey, "go-secret")
        XCTAssertEqual(settings.config.model, "kimi-k3")
        keys.failWrites = false
        settings.reset()
        XCTAssertNil(keys.values["opencode_go"])
        XCTAssertEqual(keys.values["openrouter"], "router-secret")
        XCTAssertEqual(settings.apiKey, "")
        XCTAssertEqual(settings.config.model, "")
    }

    func testHTTPConsentDoesNotFollowAChangedOriginAndRestoresWithSavedProfile() throws {
        defaults.set(true, forKey: migrationKey)
        let settings = AssistantSettings(defaults: defaults, keyStore: MemoryKeys([:]))
        settings.selectProvider(.anthropic)
        settings.config.baseURL = "http://first.example/v1"
        settings.config.allowInsecureHTTP = true
        settings.config.baseURL = "http://first.example/proxy/v1"
        XCTAssertTrue(settings.config.allowInsecureHTTP)
        settings.selectProvider(.openRouter)
        settings.selectProvider(.anthropic)
        XCTAssertTrue(settings.config.allowInsecureHTTP)
        settings.config.baseURL = "http://second.example/v1"
        XCTAssertFalse(settings.config.allowInsecureHTTP)
        XCTAssertFalse(AssistantSettings(defaults: defaults, keyStore: MemoryKeys([:])).config.allowInsecureHTTP)
    }

    func testWhitespaceInCustomAddressCannotCarryKeyOrHTTPConsentToAnotherHost() {
        defaults.set(true, forKey: migrationKey)
        let settings = AssistantSettings(defaults: defaults, keyStore: MemoryKeys([:]))
        settings.selectProvider(.anthropic)
        settings.config.baseURL = " http://first.example/v1 "
        settings.apiKey = "fixture-first-key"
        settings.config.allowInsecureHTTP = true
        settings.config.baseURL = " http://second.example/v1 "
        XCTAssertEqual(settings.apiKey, "")
        XCTAssertFalse(settings.config.allowInsecureHTTP)
    }

    func testExistingScopedKeyWinsOverLegacyAndCleansBuildTwoResidue() throws {
        try save(.init(kind: .openCodeGo, model: "kimi-k3"))
        let keys = MemoryKeys(["default": "stale", "opencode_go": "new-key"])
        XCTAssertEqual(AssistantSettings(defaults: defaults, keyStore: keys).apiKey, "new-key")
        XCTAssertNil(keys.values["default"])
        keys.values["default"] = "new-key"
        _ = AssistantSettings(defaults: defaults, keyStore: keys)
        XCTAssertNil(keys.values["default"])
    }
}

private final class MemoryKeys: AssistantKeyStoring {
    var values: [String: String]
    var failReads = false
    var failWrites = false
    var writeCount = 0
    init(_ values: [String: String]) { self.values = values }
    func read(account: String) throws -> String? {
        if failReads { throw AssistantKeyError.verificationFailed }
        return values[account]
    }
    func write(_ value: String?, account: String) throws {
        writeCount += 1
        if failWrites { throw AssistantKeyError.verificationFailed }
        values[account] = value
    }
}
