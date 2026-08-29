#if canImport(Security)
import Foundation
import Security

/// Keychain-backed secure storage for the application session tokens.
///
/// Tokens are stored as an encrypted generic-password item accessible only
/// after first unlock and only on this device, never synced to iCloud.
public struct KeychainSessionStore: SessionStore {
    private let service: String
    private let account: String

    public init(service: String = "com.voxa.app.session", account: String = "primary") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() throws -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = item as? Data else { return nil }
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func save(_ session: AuthSession) throws {
        let data = try JSONEncoder().encode(session)

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
            return
        }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

public enum KeychainError: Error, Equatable {
    case unexpectedStatus(OSStatus)
}
#endif
