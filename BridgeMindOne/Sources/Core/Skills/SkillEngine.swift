//
// Skill.swift
// Skill model definition
//

import Foundation

public struct Skill: Codable, Equatable, Identifiable, Sendable {
 public let id: String
 public let name: String
 public let description: String
 public let version: String
 public let engine: String
 public let content: String
 public let contentHash: String
 public let source: SkillSource
 public let installedAt: Date

 public init(
 id: String,
 name: String,
 description: String,
 version: String,
 engine: String,
 content: String,
 source: SkillSource = .builtin,
 installedAt: Date = Date()
 ) {
 self.id = id
 self.name = name
 self.description = description
 self.version = version
 self.engine = engine
 self.content = content
 self.contentHash = SHA256.hash(data: Data(content.utf8)).compactMap { String(format: "%02x", $0) }.joined()
 self.source = source
 self.installedAt = installedAt
 }
}

public enum SkillSource: String, Codable, Equatable {
 case builtin
 case user
 case project
}

// MARK: - Skill Frontmatter

public struct SkillFrontmatter: Codable, Equatable {
 public let name: String
 public let description: String
 public let version: String
 public let engine: String

 public init(name: String, description: String, version: String = "1.0.0", engine: String = "claude") {
 self.name = name
 self.description = description
 self.version = version
 self.engine = engine
 }
}

// MARK: - Skill Parser

public enum SkillParser {
 public static func parse(_ content: String) throws -> (frontmatter: SkillFrontmatter, body: String) {
 // Split frontmatter from body
 let components = content.components(separatedBy: "---")

 guard components.count >= 3 else {
 throw SkillError.invalidFormat("Missing YAML frontmatter delimiters")
 }

 let frontmatterString = components[1].trimmingCharacters(in: .whitespacesAndNewlines)
 let body = components[2...].joined(separator: "---").trimmingCharacters(in: .whitespacesAndNewlines)

 let frontmatter = try YAMLDecoder().decode(SkillFrontmatter.self, from: frontmatterString)

 return (frontmatter, body)
 }

 public static func skillId(from name: String) -> String {
 "skill-\(name.replacingOccurrences(of: " ", with: "-"))"
 }
}

// MARK: - Simple YAML Decoder (no external dependency)

private struct YAMLDecoder {
 func decode<T: Decodable>(_ type: T.Type, from yaml: String) throws -> T {
 let dict = try parseSimpleYAML(yaml)
 let data = try JSONSerialization.data(withJSONObject: dict)
 return try JSONDecoder().decode(T.self, from: data)
 }

 private func parseSimpleYAML(_ yaml: String) throws -> [String: Any] {
 var result: [String: Any] = [:]
 var lines = yaml.components(separatedBy: .newlines)

 var currentKey: String?
 var currentMultiline: [String] = []
 var inMultiline = false

 for line in lines {
 let trimmed = line.trimmingCharacters(in: .whitespaces)

 if inMultiline {
 if trimmed.hasPrefix(" ") || trimmed.isEmpty {
 currentMultiline.append(trimmed)
 } else {
 // End multiline
 if let key = currentKey {
 result[key] = currentMultiline.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
 }
 currentMultiline = []
 inMultiline = false
 currentKey = nil
 // Reprocess this line
 }
 }

 if !inMultiline, let colonIndex = trimmed.firstIndex(of: ":") {
 let key = String(trimmed[..<colonIndex]).trimmingCharacters(in: .whitespaces)
 let valuePart = String(trimmed[trimmed.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)

 if valuePart.hasPrefix("|") || valuePart.hasPrefix(">") {
 currentKey = key
 inMultiline = true
 currentMultiline = []
 } else if !valuePart.isEmpty {
 result[key] = parseValue(valuePart)
 currentKey = nil
 } else {
 // Might start multiline on next line
 currentKey = key
 }
 }
 }

 // Flush remaining multiline
 if inMultiline, let key = currentKey {
 result[key] = currentMultiline.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
 }

 return result
 }

 private func parseValue(_ string: String) -> Any {
 if string == "true" { return true }
 if string == "false" { return false }
 if string == "null" || string == "~" { return NSNull() }
 if let num = Double(string) { return num }
 if let int = Int(string) { return int }
 // Remove quotes
 if (string.hasPrefix("\"") && string.hasSuffix("\"")) ||
 (string.hasPrefix("'") && string.hasSuffix("'")) {
 return String(string.dropFirst().dropLast())
 }
 return string
 }
}

// MARK: - Skill Engine

public actor SkillEngine {
 public static let shared = SkillEngine()

 private var skills: [String: Skill] = [:]
 private let builtInURL: URL
 private var userSkillsURL: URL?

 public init() {
 let resourcesURL = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Skills")
 self.builtInURL = resourcesURL
 self.userSkillsURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
 .appendingPathComponent("BridgeMind/skills", isDirectory: true)
 }

 public func loadBuiltInSkills() async {
 guard FileManager.default.fileExists(atPath: builtInURL.path) else { return }

 do {
 let files = try FileManager.default.contentsOfDirectory(at: builtInURL, includingPropertiesForKeys: nil)
 for file in files where file.pathExtension == "md" {
 try await loadSkill(from: file, source: .builtin)
 }
 } catch {
 // Log but continue
 }
 }

 public func loadUserSkills() async {
 guard let url = userSkillsURL, FileManager.default.fileExists(atPath: url.path) else { return }

 do {
 let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
 for file in files where file.pathExtension == "md" {
 try await loadSkill(from: file, source: .user)
 }
 } catch {
 // Log but continue
 }
 }

 public func skill(named name: String) async -> Skill? {
 if let skill = skills[name] { return skill }

 // Try loading from user directory
 if let url = userSkillsURL {
 let fileURL = url.appendingPathComponent("\(name).md")
 if FileManager.default.fileExists(atPath: fileURL.path) {
 try? await loadSkill(from: fileURL, source: .user)
 return skills[name]
 }
 }

 return nil
 }

 public func allSkills() async -> [Skill] {
 await loadUserSkills()
 return Array(skills.values).sorted { $0.name < $1.name }
 }

 public func skills(for engine: String) async -> [Skill] {
 let all = await allSkills()
 return all.filter { $0.engine == engine || $0.engine == "*" }
 }

 public func injectSkill(into context: [String], skill: Skill) -> [String] {
 var injected = context
 injected.append("## Skill: \(skill.name)")
 injected.append(skill.description)
 injected.append("")
 injected.append(skill.content)
 injected.append("")
 return injected
 }

 public func removeSkill(named name: String) async {
 skills.removeValue(forKey: name)

 if let url = userSkillsURL {
 let fileURL = url.appendingPathComponent("\(name).md")
 try? FileManager.default.removeItem(at: fileURL)
 }
 }

 // MARK: - Private

 private func loadSkill(from url: URL, source: SkillSource) async throws {
 let content = try String(contentsOf: url, encoding: .utf8)
 let (frontmatter, body) = try SkillParser.parse(content)
 let id = SkillParser.skillId(from: frontmatter.name)

 let skill = Skill(
 id: id,
 name: frontmatter.name,
 description: frontmatter.description,
 version: frontmatter.version,
 engine: frontmatter.engine,
 content: body,
 source: source
 )

 skills[id] = skill
 }

 public func watchSkillsFolder() {
 // Watch for changes to user skills directory
 // Not implemented — would use FSEvents or DispatchSourceFileSystemObject
 }
}

// MARK: - Errors

public enum SkillError: Error, Equatable {
 case invalidFormat(String)
 case notFound(String)
 case loadFailed(String)

 public var localizedDescription: String {
 switch self {
 case .invalidFormat(let msg): return "Invalid skill format: \(msg)"
 case .notFound(let name): return "Skill not found: \(name)"
 case .loadFailed(let msg): return "Failed to load skill: \(msg)"
 }
 }
}
