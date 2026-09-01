//
// OAuthFlows.swift
// OAuth 2.0 + PKCE implementation for MCP plugins
//

import Foundation
import CryptoKit

// MARK: - OAuth Protocols

public protocol MCPOAuthURLValidating: Sendable {
 func isValidOAuthURL(_ url: URL) -> Bool
}

public protocol MCPOAuthScopeSelecting: Sendable {
 func selectScopes(for plugin: PluginIdentity) -> [String]
}

public protocol MCPHTTPClientAuthorizer {
 func authorize(request: inout URLRequest, session: MCPSession?) async throws
}

public protocol MCPOAuthTokenRequesting: Sendable {
 func requestToken(
 plugin: PluginIdentity,
 authorizationCode: String,
 codeVerifier: String
 ) async throws -> OAuthToken
}

public protocol MCPOAuthClientRegistering: Sendable {
 func registerClient(for plugin: PluginIdentity) async throws -> OAuthClientRegistration
}

public protocol MCPOAuthDiscoveryFetching: Sendable {
 func fetchDiscovery(for plugin: PluginIdentity) async throws -> OAuthDiscovery
}

public protocol MCPOAuthMetadataDiscovering: Sendable {
 func discoverMetadata(for plugin: PluginIdentity) async throws -> OAuthMetadata
}

public protocol MCPOAuthAuthorizationDelegate: Sendable {
 func handleAuthorizationURL(_ url: URL) async throws -> String
}

public protocol MCPOAuthWWWAuthenticateParsing: Sendable {
 func parseWWWAuthenticate(_ header: String) -> OAuthChallenge?
}

public protocol MCPOAuthAuthorizationCodeFlowing: Sendable {
 func executeAuthorizationCodeFlow(plugin: PluginIdentity) async throws -> OAuthToken
}

// MARK: - OAuth Models

public struct OAuthToken: Codable, Equatable {
 public let accessToken: String
 public let refreshToken: String?
 public let tokenType: String
 public let expiresIn: TimeInterval?
 public let scope: String?
 public let createdAt: Date

 public init(accessToken: String, refreshToken: String? = nil, tokenType: String = "Bearer", expiresIn: TimeInterval? = nil, scope: String? = nil) {
 self.accessToken = accessToken
 self.refreshToken = refreshToken
 self.tokenType = tokenType
 self.expiresIn = expiresIn
 self.scope = scope
 self.createdAt = Date()
 }

 public var isExpired: Bool {
 guard let expiresIn = expiresIn else { return false }
 return Date().timeIntervalSince(createdAt) > expiresIn
 }
}

public struct OAuthClientRegistration: Codable, Equatable {
 public let clientId: String
 public let clientSecret: String?
 public let redirectURI: String
 public let scopes: [String]
}

public struct OAuthDiscovery: Codable, Equatable {
 public let issuer: URL
 public let authorizationEndpoint: URL
 public let tokenEndpoint: URL
 public let registrationEndpoint: URL?
 public let scopesSupported: [String]?
}

public struct OAuthMetadata: Codable, Equatable {
 public let issuer: String
 public let authorizationEndpoint: String
 public let tokenEndpoint: String
 public let registrationEndpoint: String?
 public let scopesSupported: [String]?
 public let responseTypesSupported: [String]
 public let subjectTypesSupported: [String]
 public let idTokenSigningAlgValuesSupported: [String]
}

public struct OAuthChallenge: Codable, Equatable {
 public let realm: String?
 public let scope: String?
 public let error: String?
 public let errorDescription: String?

 public init(realm: String? = nil, scope: String? = nil, error: String? = nil, errorDescription: String? = nil) {
 self.realm = realm
 self.scope = scope
 self.error = error
 self.errorDescription = errorDescription
 }
}

// MARK: - Plugin Identity

public struct PluginIdentity: Codable, Equatable, Hashable, Sendable {
 public let id: String
 public let displayName: String
 public let type: PluginType
 public let authType: PluginAuthType
 public let mcpURL: URL?
 public let apiKeyEnv: String?
 public let scopes: [String]?

 public init(id: String, displayName: String, type: PluginType, authType: PluginAuthType, mcpURL: URL? = nil, apiKeyEnv: String? = nil, scopes: [String]? = nil) {
 self.id = id
 self.displayName = displayName
 self.type = type
 self.authType = authType
 self.mcpURL = mcpURL
 self.apiKeyEnv = apiKeyEnv
 self.scopes = scopes
 }
}

public enum PluginType: String, Codable, Equatable, Sendable {
    case remote // HTTP MCP server
    case local // stdio MCP server
    case oauth // OAuth-based plugin
    case builtin // Built into BridgeMind
}

public enum PluginAuthType: String, Codable, Equatable, Sendable {
    case none // No auth needed
    case apiKey // Simple API key
    case oauth // Full OAuth 2.0
}

// MARK: - PKCE Generator

public struct PKCEChallenge: Sendable {
 public let codeVerifier: String
 public let codeChallenge: String
 public let method: String

 public init() {
 // RFC 7636: code_verifier is 43-128 chars from unreserved set
 let verifierData = Data((0..<64).map { _ in UInt8.random(in: 0...255) })
 self.codeVerifier = PKCEChallenge.base64URLEncode(verifierData)

 // SHA256 + base64url encode
 let challengeData = SHA256.hash(data: verifierData)
 self.codeChallenge = PKCEChallenge.base64URLEncode(Data(challengeData))
 self.method = "S256"
 }

 private static func base64URLEncode(_ data: Data) -> String {
 data.base64EncodedString()
 .replacingOccurrences(of: "+", with: "-")
 .replacingOccurrences(of: "/", with: "_")
 .trimmingCharacters(in: .whitespaces)
 .replacingOccurrences(of: "=", with: "")
 }
}

// MARK: - Credential Store

public protocol MCPTokenStorage: Sendable {
 func storeToken(_ token: OAuthToken, for plugin: PluginIdentity) async throws
 func retrieveToken(for plugin: PluginIdentity) async throws -> OAuthToken?
 func deleteToken(for plugin: PluginIdentity) async throws
 func allTokens() async throws -> [PluginIdentity: OAuthToken]
}
