import Foundation
import Security
import LocalAuthentication

public enum GarminKeychain {
    private static let service = "local.traininghub.mac.garmin-personal-api"
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "personal-api-key"] }
    public static func hasKey() throws -> Bool {
        var values = query
        values[kSecReturnAttributes as String] = true
        let context = LAContext(); context.interactionNotAllowed = true
        values[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(values as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw failure(status) }
        return true
    }
    public static func save(_ key: String) throws {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r"), key.count < 10_000 else { throw HubError.message("Enter a valid Personal API key.") }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var values = query
            values[kSecValueData as String] = data
            values[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(values as CFDictionary, nil) == errSecSuccess else { throw HubError.message("The key could not be stored in Keychain.") }
        } else if status != errSecSuccess { throw failure(status) }
    }
    public static func read() throws -> String {
        var values = query
        values[kSecReturnData as String] = true
        values[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(values as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            if status == errSecItemNotFound { throw HubError.message("Add your Garmin Personal API key in Settings first.") }
            throw failure(status)
        }
        return key
    }
    public static func remove() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw failure(status) }
    }
    private static func failure(_ status: OSStatus) -> HubError { .message("Keychain access failed (\(status)). Unlock your Mac or allow access in Keychain, then retry.") }
}
