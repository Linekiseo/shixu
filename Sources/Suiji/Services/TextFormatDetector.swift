import Foundation

enum TextFormatDetector {
    static func detect(_ rawText: String) -> TextContentFormat? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if isJSON(text) { return .json }
        if markdownScore(text) >= 4 { return .markdown }
        if matches(text, #"(?is)^\s*<!doctype\s+html|^\s*<html\b|<body\b|<div\b[^>]*>"#) { return .html }
        if matches(text, #"(?is)^\s*<\?xml\b|^\s*<[A-Za-z][\w:.-]*\b[^>]*>.*</[A-Za-z][\w:.-]*>\s*$"#) { return .xml }
        if looksLikeCSS(text) { return .css }
        if looksLikeSwift(text) { return .swift }
        if looksLikePython(text) { return .python }
        if looksLikeTypeScript(text) { return .typescript }
        if looksLikeJavaScript(text) { return .javascript }
        if looksLikeSQL(text) { return .sql }
        if looksLikeShell(text) { return .shell }
        if looksLikeCSV(text) { return .csv }
        if looksLikeYAML(text) { return .yaml }

        let lines = nonEmptyLines(text)
        if text.count >= 240 || lines.count >= 8 { return .plainText }
        return nil
    }

    static func suggestedTitle(for text: String, format: TextContentFormat) -> String? {
        let lines = text.components(separatedBy: .newlines)
        if format == .markdown,
           let heading = lines.first(where: { $0.range(of: #"^\s*#{1,6}\s+\S"#, options: .regularExpression) != nil }) {
            let title = heading.replacingOccurrences(of: #"^\s*#{1,6}\s+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return title }
        }

        if let firstComment = lines.first(where: { line in
            line.range(of: #"^\s*(?://|#|--|/\*)\s*\S"#, options: .regularExpression) != nil
        }) {
            let title = firstComment
                .replacingOccurrences(of: #"^\s*(?://|#|--|/\*)\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "*/", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty { return String(title.prefix(48)) }
        }
        return nil
    }

    static func fileName(title: String, format: TextContentFormat) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>\n\r\t")
        let cleaned = title
            .components(separatedBy: invalid)
            .joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty ? "未命名\(format.title)" : String(cleaned.prefix(64))
        return "\(base).\(format.fileExtension)"
    }

    private static func isJSON(_ text: String) -> Bool {
        guard let first = text.first, first == "{" || first == "[",
              let data = text.data(using: .utf8) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) != nil
    }

    private static func markdownScore(_ text: String) -> Int {
        var score = 0
        if matches(text, #"(?m)^\s*#{1,6}\s+\S"#) { score += 3 }
        if matches(text, #"(?m)^\s*```[A-Za-z0-9_-]*\s*$"#) { score += 4 }
        if matchCount(text, #"(?m)^\s*[-*+]\s+\S"#) >= 2 { score += 2 }
        if matchCount(text, #"(?m)^\s*\d+[.)]\s+\S"#) >= 2 { score += 2 }
        if matches(text, #"\[[^\]]+\]\([^\)]+\)"#) { score += 2 }
        if matches(text, #"(?m)^\s*>\s+\S"#) { score += 1 }
        if matches(text, #"(?m)^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$"#) { score += 3 }
        if matches(text, #"(\*\*|__)[^\n]+(\*\*|__)"#) { score += 1 }
        if text.hasPrefix("---\n") && text.contains("\n---\n") { score += 2 }
        return score
    }

    private static func looksLikeSwift(_ text: String) -> Bool {
        matches(text, #"(?m)^\s*import\s+(SwiftUI|Foundation|AppKit|UIKit)\b"#)
            || (matches(text, #"\b(struct|class|enum|actor)\s+[A-Z]\w*"#) && matches(text, #"\b(let|var|func)\b"#))
            || matches(text, #"@(State|Binding|MainActor|Observable)\b"#)
    }

    private static func looksLikePython(_ text: String) -> Bool {
        matches(text, #"(?m)^\s*(from\s+[\w.]+\s+import|import\s+[\w.]+|def\s+\w+\s*\(|class\s+\w+\s*[:(])"#)
            || text.contains("if __name__ == \"__main__\"")
    }

    private static func looksLikeTypeScript(_ text: String) -> Bool {
        matches(text, #"(?m)^\s*(interface|type|enum)\s+[A-Z]\w*"#)
            || matches(text, #"\b(const|let|function)\s+\w+\s*:\s*(string|number|boolean|unknown|[A-Z]\w*)"#)
    }

    private static func looksLikeJavaScript(_ text: String) -> Bool {
        matches(text, #"(?m)^\s*(const|let|var)\s+\w+\s*="#)
            && (text.contains("=>") || matches(text, #"\b(function|async|await|console\.)\b"#))
    }

    private static func looksLikeSQL(_ text: String) -> Bool {
        matches(text, #"(?is)\bSELECT\b.+\bFROM\b|\bINSERT\s+INTO\b|\bCREATE\s+TABLE\b|\bUPDATE\b.+\bSET\b"#)
    }

    private static func looksLikeShell(_ text: String) -> Bool {
        text.hasPrefix("#!/bin/bash") || text.hasPrefix("#!/usr/bin/env bash") || text.hasPrefix("#!/bin/zsh")
            || (matchCount(text, #"(?m)^\s*(export\s+\w+=|echo\s+|cd\s+|if\s+\[|for\s+\w+\s+in\s+)"#) >= 2)
    }

    private static func looksLikeCSS(_ text: String) -> Bool {
        matchCount(text, #"(?m)^\s*[.#]?[A-Za-z][\w\s>+~:.,#\[\]=\"'-]*\s*\{\s*$"#) >= 1
            && matchCount(text, #"(?m)^\s*[\w-]+\s*:\s*[^;{}]+;\s*$"#) >= 2
    }

    private static func looksLikeCSV(_ text: String) -> Bool {
        let lines = nonEmptyLines(text)
        guard lines.count >= 3 else { return false }
        for delimiter in [",", "\t", ";"] {
            let counts = lines.prefix(8).map { $0.components(separatedBy: delimiter).count }
            if let first = counts.first, first >= 2, counts.allSatisfy({ $0 == first }) { return true }
        }
        return false
    }

    private static func looksLikeYAML(_ text: String) -> Bool {
        let keyLines = matchCount(text, #"(?m)^\s*[A-Za-z_][\w.-]*\s*:\s*\S.*$"#)
        let listLines = matchCount(text, #"(?m)^\s*-\s+([A-Za-z_][\w.-]*\s*:|\S)"#)
        return keyLines >= 3 || (keyLines >= 2 && listLines >= 2)
    }

    private static func nonEmptyLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func matchCount(_ text: String, _ pattern: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }
        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }
}
