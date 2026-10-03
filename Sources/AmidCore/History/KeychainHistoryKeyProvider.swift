import Foundation
import CryptoKit
import Security
import LocalAuthentication

public enum HistoryStorageError: Error { case keychain(OSStatus), invalidKey, invalidEnvelope, unsupportedVersion(Int), unsafePath }
public struct KeychainHistoryKeyProvider: HistoryKeyProvider {
    private let service: String
    public init(testNamespace: UUID? = nil) { service = "com.madeordinary.amid.history" + (testNamespace.map { ".test." + $0.uuidString } ?? "") }
    public func key() throws -> SymmetricKey { try readKey(createIfMissing:true) }
    public func existingKey() throws -> SymmetricKey { try readKey(createIfMissing:false) }
    private func readKey(createIfMissing: Bool) throws -> SymmetricKey {
        let query: [String:Any] = [kSecClass as String:kSecClassGenericPassword, kSecAttrService as String:service, kSecAttrAccount as String:"encryption-key-v1"]
        let context = LAContext(); context.interactionNotAllowed = true
        var read = query; read[kSecUseAuthenticationContext as String] = context; read[kSecReturnData as String] = true; read[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &result)
        if status == errSecSuccess { guard let data = result as? Data, data.count == 32 else { throw HistoryStorageError.invalidKey }; return SymmetricKey(data:data) }
        guard status == errSecItemNotFound && createIfMissing else { throw HistoryStorageError.keychain(status) }
        let key = SymmetricKey(size:.bits256)
        var add = query; add[kSecValueData as String] = key.withUnsafeBytes { Data($0) }; add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(add as CFDictionary,nil)
        if added == errSecDuplicateItem { return try self.key() }
        guard added == errSecSuccess else { throw HistoryStorageError.keychain(added) }
        return key
    }
}
