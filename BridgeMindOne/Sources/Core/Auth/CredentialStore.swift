//
// CredentialStore.swift
// Secure credential storage using CryptoKit + Keychain
//

import Foundation
import Security
import CryptoKit

public actor CredentialStore: MCPTokenStorage {
 private let service = "ai.bridgemind.one"
 private let accessGroup: String?

 public init(keychainAccessGroup: String? = nil) {
 self.accessGroup = keychainAccessGroup
 }

 // MARK: - MCPTokenStorage

 public func storeToken(_ token: OAuthToken, for plugin: PluginIdentity) async throws {
 let key = tokenKey(for: plugin)
 let data = try JSONEncoder().encode(token)

 var query: [String: Any] = [
 kSecClass as String: kSecClassGenericPassword,
 kSecAttrService as String: service,
 kSecAttrAccount as String: key,
 kSecValueData as String: data,
 ]

 if let accessGroup {
 query[kSecAttrAccessGroup as String] = accessGroup
 }

 // Delete existing if present
 SecItemDelete(query as CFDictionary)

 let status = SecItemAdd(query as CFDictionary, nil)

 if status != errSecSuccess {
 throw CredentialStoreError.keychainError(status, "Failed to store token")
 }
 }

 public func retrieveToken(for plugin: PluginIdentity) async throws -> OAuthToken? {
 let key = tokenKey(for: plugin)

 var query: [String: Any] = [
 kSecClass as String: kSecClassGenericPassword,
 kSecAttrService as String: service,
 kSecAttrAccount as String: key,
 kSecReturnData as String: true,
 kSecMatchLimit as String: kSecMatchLimitOne,
 ]

 if let accessGroup {
 query[kSecAttrAccessGroup as String] = accessGroup
 }

 var result: CFTypeRef?
 let status = SecItemCopyMatching(query as CFDictionary, &result)

 guard status == errSecSuccess, let data = result as? Data else {
 if status == errSecItemNotFound { return nil }
 throw CredentialStoreError.keychainError(status, "Failed to retrieve token")
 }

 return try? JSONDecoder().decode(OAuthToken.self, from: data)
 }

 public func deleteToken(for plugin: PluginIdentity) async throws {
 let key = tokenKey(for: plugin)
 let query: [String: Any] = [
 kSecClass as String: kSecClassGenericPassword,
 kSecAttrService as String: service,
 kSecAttrAccount as String: key,
 ]

 if let accessGroup {
 query[kSecAttrAccessGroup as String] = accessGroup
 }

 SecItemDelete(query as CFDictionary)
 }

    public func allTokens() async throws -> [PluginIdentity: OAuthToken] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]

 if let accessGroup {
 query[kSecAttrAccessGroup as String] = accessGroup
 }

 var result: CFTypeRef?
 let status = SecItemCopyMatching(query as CFDictionary, &result)

 guard status == errSecSuccess, let items = result as? [[String: Any]] else {
 return [:]
 }

 var tokens: [PluginIdentity: OAuthToken] = [:]
 for item in items {
 guard let account = item[kSecAttrAccount as String] as? String,
 let data = item[kSecValueData as String] as? Data,
 let token = try? JSONDecoder().decode(OAuthToken.self, from: data) else { continue }

 let plugin = pluginIdentity(from: account)
 tokens[plugin] = token
 }

 return tokens
 }

 // MARK: - Private

 private func tokenKey(for plugin: PluginIdentity) -> String {
 "token.\(plugin.id)"
 }

 private func pluginIdentity(from key: String) -> PluginIdentity {
 let id = key.replacingOccurrences(of: "token.", with: "")
 return PluginIdentity(id: id, displayName: id, type: .remote, authType: .oauth)
 }
}

// MARK: - Errors

public enum CredentialStoreError: Error, Equatable {
 case keychainError(OSStatus, String)

 public var localizedDescription: String {
 if case .keychainError(_, let message) = self { return message }
 return "Unknown credential store error"
 }
}
