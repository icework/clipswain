import Foundation
import Security

/// Stores secrets in the Keychain: the board API key per server origin, and the LLM API key
/// used to draft tasks.
enum Keychain {
    private static let boardService = "space.icework.clipswain.board-key"
    private static let assistantService = "space.icework.clipswain.llm-key"

    static func token(for server: String) throws -> String? {
        try read(service: boardService, account: server)
    }

    static func setToken(_ token: String?, for server: String) throws {
        try write(token, service: boardService, account: server)
    }

    static func readAssistantKey(account: String) throws -> String? {
        try read(service: assistantService, account: account)
    }

    static func writeAssistantKey(_ value: String?, account: String) throws {
        try write(value, service: assistantService, account: account)
    }

    private static func read(service: String, account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw AssistantKeyError.status(status) }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw AssistantKeyError.status(errSecDecode)
        }
        return value
    }

    private static func write(_ value: String?, service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let value, !value.isEmpty else {
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else { throw AssistantKeyError.status(status) }
            return
        }
        // Updating in place preserves the previous credential when storage is unavailable.
        // Only add when no existing item was found; never delete a key before replacing it.
        let attributes = [kSecValueData as String: Data(value.utf8)]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = Data(value.utf8)
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw AssistantKeyError.status(status) }
    }
}

protocol BoardKeyStoring {
    func read(account: String) throws -> String?
    func write(_ value: String?, account: String) throws
}

struct KeychainBoardKeyStore: BoardKeyStoring {
    func read(account: String) throws -> String? { try Keychain.token(for: account) }
    func write(_ value: String?, account: String) throws { try Keychain.setToken(value, for: account) }
}

protocol AssistantKeyStoring {
    func read(account: String) throws -> String?
    func write(_ value: String?, account: String) throws
}

struct KeychainAssistantKeyStore: AssistantKeyStoring {
    func read(account: String) throws -> String? { try Keychain.readAssistantKey(account: account) }
    func write(_ value: String?, account: String) throws { try Keychain.writeAssistantKey(value, account: account) }
}

enum AssistantKeyError: LocalizedError {
    case status(OSStatus)
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .status(let status): return AppL10n.text("keychain.unavailable", "Keychain is temporarily unavailable (\(String(status))). Unlock your device and try again.")
        case .verificationFailed: return AppL10n.text("keychain.verification", "The API key could not be verified after saving. The previous key was preserved. Please try again.")
        }
    }
}
