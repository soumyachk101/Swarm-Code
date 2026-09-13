import Foundation

/// Block-level Markdown for agent output. Inline styling is handled by `AttributedString`.
enum MarkdownBlock: Hashable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case code(language: String?, code: String)
    case list(ordered: Bool, start: Int, items: [MarkdownListItem])
    case quote([MarkdownBlock])
    case table(header: [String], rows: [[String]])
    case rule
}

struct MarkdownListItem: Hashable, Sendable {
    var text: String
    var checked: Bool?
    var children: [MarkdownBlock]
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        return parse(lines[...])
    }

    private static func parse(_ lines: ArraySlice<String>) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var index = lines.startIndex
        var paragraph: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph.removeAll()
        }

        while index < lines.endIndex {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                index += 1
                continue
            }

            if let fence = fenceMarker(trimmed) {
                flushParagraph()
                let language = String(trimmed.dropFirst(fence.count)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.endIndex {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(fence), candidate.allSatisfy({ $0 == fence.first }) { index += 1; break }
                    code.append(lines[index])
                    index += 1
                }
                blocks.append(.code(language: language.isEmpty ? nil : language, code: code.joined(separator: "\n")))
                continue
            }

            if let heading = headingLevel(trimmed) {
                flushParagraph()
                let content = trimmed.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: heading, text: content.trimmingCharacters(in: CharacterSet(charactersIn: "# "))))
                index += 1
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                index += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while index < lines.endIndex {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    var content = candidate.dropFirst()
                    if content.hasPrefix(" ") { content = content.dropFirst() }
                    quoted.append(String(content))
                    index += 1
                }
                blocks.append(.quote(parse(quoted[...])))
                continue
            }

            if index + 1 < lines.endIndex, trimmed.contains("|"), isTableDelimiter(lines[index + 1]) {
                flushParagraph()
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.endIndex {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard !candidate.isEmpty, candidate.contains("|") else { break }
                    rows.append(tableCells(candidate))
                    index += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            if let marker = listMarker(line), paragraph.isEmpty || !marker.ordered || marker.start == 1 {
                flushParagraph()
                let (list, next) = parseList(lines, from: index)
                blocks.append(list)
                index = next
                continue
            }

            paragraph.append(line)
            index += 1
        }
        flushParagraph()
        return blocks
    }

    private struct ListMarker {
        var indent: Int
        var ordered: Bool
        var start: Int
        var contentOffset: Int
        var content: String
    }

    private static func parseList(_ lines: ArraySlice<String>, from start: Int) -> (MarkdownBlock, Int) {
        guard let first = listMarker(lines[start]) else { return (.paragraph(lines[start]), start + 1) }
        var items: [MarkdownListItem] = []
        var index = start
        var currentText: [String] = []
        var childLines: [String] = []
        var hasItem = false

        func flushItem() {
            guard hasItem else { return }
            var text = currentText.joined(separator: "\n").trimmingCharacters(in: .whitespaces)
            var checked: Bool?
            if text.hasPrefix("[ ] ") {
                checked = false
                text.removeFirst(4)
            } else if text.lowercased().hasPrefix("[x] ") {
                checked = true
                text.removeFirst(4)
            }
            items.append(MarkdownListItem(text: text, checked: checked, children: parse(childLines[...])))
            currentText.removeAll()
            childLines.removeAll()
        }

        while index < lines.endIndex {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                let next = index + 1
                if next < lines.endIndex, indentation(lines[next]) > first.indent, !lines[next].trimmingCharacters(in: .whitespaces).isEmpty {
                    childLines.append("")
                    index += 1
                    continue
                }
                if next < lines.endIndex, let marker = listMarker(lines[next]), marker.indent == first.indent, marker.ordered == first.ordered {
                    index += 1
                    continue
                }
                break
            }
            if let marker = listMarker(line), marker.indent <= first.indent {
                guard marker.ordered == first.ordered else { break }
                flushItem()
                hasItem = true
                currentText = [marker.content]
                index += 1
                continue
            }
            if indentation(line) > first.indent {
                let dropped = String(line.dropFirst(min(indentation(line), first.contentOffset)))
                if childLines.isEmpty, listMarker(line) == nil, fenceMarker(trimmed) == nil {
                    currentText.append(trimmed)
                } else {
                    childLines.append(dropped)
                }
                index += 1
                continue
            }
            if childLines.isEmpty, headingLevel(trimmed) == nil, fenceMarker(trimmed) == nil, !trimmed.hasPrefix(">") {
                currentText.append(trimmed)
                index += 1
                continue
            }
            break
        }
        flushItem()
        return (.list(ordered: first.ordered, start: first.start, items: items), index)
    }

    private static func listMarker(_ line: String) -> ListMarker? {
        let indent = indentation(line)
        let body = line.dropFirst(indent)
        if let first = body.first, "-*+".contains(first) {
            let rest = body.dropFirst()
            guard rest.hasPrefix(" ") || rest.hasPrefix("\t") else { return nil }
            let content = rest.drop(while: { $0 == " " || $0 == "\t" })
            return ListMarker(indent: indent, ordered: false, start: 1, contentOffset: indent + 2, content: String(content))
        }
        let digits = body.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = body.dropFirst(digits.count)
        guard let delimiter = rest.first, delimiter == "." || delimiter == ")" else { return nil }
        let afterDelimiter = rest.dropFirst()
        guard afterDelimiter.hasPrefix(" ") || afterDelimiter.isEmpty else { return nil }
        let content = afterDelimiter.drop(while: { $0 == " " })
        return ListMarker(indent: indent, ordered: true, start: Int(digits) ?? 1, contentOffset: indent + digits.count + 2, content: String(content))
    }

    private static func indentation(_ line: String) -> Int {
        var count = 0
        for character in line {
            if character == " " { count += 1 } else if character == "\t" { count += 4 } else { break }
        }
        return count
    }

    private static func fenceMarker(_ trimmed: String) -> String? {
        for marker in ["```", "~~~"] where trimmed.hasPrefix(marker) {
            let fenceCharacter = marker.first!
            return String(trimmed.prefix(while: { $0 == fenceCharacter }))
        }
        return nil
    }

    private static func headingLevel(_ trimmed: String) -> Int? {
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }
        let rest = trimmed.dropFirst(hashes)
        return rest.isEmpty || rest.hasPrefix(" ") ? hashes : nil
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    private static func isTableDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }
        return trimmed.allSatisfy { "|:- ".contains($0) }
    }

    private static func tableCells(_ line: String) -> [String] {
        var content = line.trimmingCharacters(in: .whitespaces)
        if content.hasPrefix("|") { content.removeFirst() }
        if content.hasSuffix("|") { content.removeLast() }
        return content.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
