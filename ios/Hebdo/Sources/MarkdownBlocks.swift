import Foundation

enum BlockType: String, Equatable {
    case p, h1, h2, h3, ul, ol, todo, quote, callout, code, divider

    var isList: Bool { self == .ul || self == .ol || self == .todo }
}

struct NoteBlock: Identifiable, Equatable {
    var id = UUID()
    var type: BlockType
    var text: String = ""
    var indent: Int = 0
    var checked: Bool = false
    var kind: String = "NOTE"
    var lang: String = ""
}

enum MarkdownBlocks {
    static let calloutKinds = ["NOTE", "TIP", "IMPORTANT", "WARNING", "CAUTION"]
    static let calloutIcons: [String: String] = [
        "NOTE": "💡",
        "TIP": "✨",
        "IMPORTANT": "❗",
        "WARNING": "⚠️",
        "CAUTION": "🔥",
    ]

    static func parse(_ md: String) -> [NoteBlock] {
        let lines = md.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var blocks: [NoteBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { i += 1; continue }

            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let indent = min(6, leadingSpaces / 2)

            if t.hasPrefix("```") {
                let lang = String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(NoteBlock(type: .code, text: codeLines.joined(separator: "\n"), lang: lang))
                i += 1
                continue
            }

            if t.hasPrefix(">"), let kind = parseCalloutKind(t) {
                var body: [String] = []
                while i + 1 < lines.count && lines[i + 1].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    i += 1
                    var stripped = lines[i].trimmingCharacters(in: .whitespaces)
                    stripped = String(stripped.dropFirst(1))
                    if stripped.hasPrefix(" ") { stripped = String(stripped.dropFirst(1)) }
                    body.append(stripped)
                }
                blocks.append(NoteBlock(type: .callout, text: body.joined(separator: " "), kind: kind))
                i += 1
                continue
            }

            if t.hasPrefix("### ") {
                blocks.append(NoteBlock(type: .h3, text: String(t.dropFirst(4))))
            } else if t.hasPrefix("## ") {
                blocks.append(NoteBlock(type: .h2, text: String(t.dropFirst(3))))
            } else if t.hasPrefix("# ") {
                blocks.append(NoteBlock(type: .h1, text: String(t.dropFirst(2))))
            } else if t == "---" || t == "***" || t == "___" {
                blocks.append(NoteBlock(type: .divider))
            } else if let todo = parseTodo(t) {
                blocks.append(NoteBlock(type: .todo, text: todo.text, indent: indent, checked: todo.checked))
            } else if t.hasPrefix("- ") || t.hasPrefix("* ") || t.hasPrefix("+ ") {
                blocks.append(NoteBlock(type: .ul, text: String(t.dropFirst(2)), indent: indent))
            } else if let olText = parseOrdered(t) {
                blocks.append(NoteBlock(type: .ol, text: olText, indent: indent))
            } else if t.hasPrefix(">") {
                var q = String(t.dropFirst(1))
                if q.hasPrefix(" ") { q = String(q.dropFirst(1)) }
                blocks.append(NoteBlock(type: .quote, text: q))
            } else {
                blocks.append(NoteBlock(type: .p, text: t))
            }
            i += 1
        }

        if blocks.isEmpty {
            blocks.append(NoteBlock(type: .p))
        }
        return blocks
    }

    static func serialize(_ blocks: [NoteBlock]) -> String {
        var out = ""
        var counters: [Int] = []
        var prevType: BlockType? = nil
        var prevIndent = 0

        for b in blocks {
            if b.type == .p && b.text.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            var num = 0
            if b.type == .ol {
                let lvl = b.indent
                if counters.count <= lvl {
                    counters.append(contentsOf: repeatElement(0, count: lvl + 1 - counters.count))
                } else {
                    counters = Array(counters.prefix(lvl + 1))
                }
                counters[lvl] += 1
                num = counters[lvl]
            } else if !b.type.isList {
                counters.removeAll()
            }

            let tight: Bool
            if let pt = prevType, pt.isList && b.type.isList && (pt == b.type || b.indent > 0 || prevIndent > 0) {
                tight = true
            } else {
                tight = false
            }

            if !out.isEmpty { out += tight ? "\n" : "\n\n" }
            out += serializeBlock(b, olNum: num)
            prevType = b.type
            prevIndent = b.indent
        }
        return out.isEmpty ? "" : out + "\n"
    }

    private static func serializeBlock(_ b: NoteBlock, olNum: Int) -> String {
        let pad = String(repeating: "  ", count: b.indent)
        switch b.type {
        case .h1: return "# " + b.text
        case .h2: return "## " + b.text
        case .h3: return "### " + b.text
        case .ul: return pad + "- " + b.text
        case .ol: return pad + "\(olNum). " + b.text
        case .todo: return pad + "- [\(b.checked ? "x" : " ")] " + b.text
        case .quote: return "> " + b.text
        case .callout: return "> [!\(b.kind.isEmpty ? "NOTE" : b.kind)]\n> " + b.text
        case .divider: return "---"
        case .code: return "```\(b.lang)\n\(b.text)\n```"
        case .p: return b.text
        }
    }

    private static func parseCalloutKind(_ t: String) -> String? {
        var s = String(t.dropFirst(1)).trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix("[!"), let end = s.firstIndex(of: "]") else { return nil }
        s = String(s[s.index(s.startIndex, offsetBy: 2)..<end])
        guard !s.isEmpty, s.allSatisfy({ $0.isLetter }) else { return nil }
        return s.uppercased()
    }

    private static func parseTodo(_ t: String) -> (checked: Bool, text: String)? {
        guard t.count >= 5 else { return nil }
        let prefixes = ["- [ ]", "- [x]", "- [X]", "* [ ]", "* [x]", "* [X]"]
        for p in prefixes where t.hasPrefix(p) {
            let rest = String(t.dropFirst(p.count))
            if rest.isEmpty || rest.hasPrefix(" ") {
                let checked = p.contains("x") || p.contains("X")
                return (checked, rest.hasPrefix(" ") ? String(rest.dropFirst(1)) : rest)
            }
        }
        return nil
    }

    private static func parseOrdered(_ t: String) -> String? {
        let digits = t.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return nil }
        let rest = t.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2))
    }
}
