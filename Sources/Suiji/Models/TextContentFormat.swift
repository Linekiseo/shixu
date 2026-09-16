import Foundation

enum TextContentFormat: String, Codable, CaseIterable, Hashable, Sendable {
    case markdown
    case json
    case yaml
    case csv
    case html
    case xml
    case swift
    case python
    case javascript
    case typescript
    case sql
    case shell
    case css
    case plainText

    var title: String {
        switch self {
        case .markdown: "Markdown"
        case .json: "JSON"
        case .yaml: "YAML"
        case .csv: "CSV"
        case .html: "HTML"
        case .xml: "XML"
        case .swift: "Swift"
        case .python: "Python"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .sql: "SQL"
        case .shell: "Shell"
        case .css: "CSS"
        case .plainText: "纯文本"
        }
    }

    var fileExtension: String {
        switch self {
        case .markdown: "md"
        case .json: "json"
        case .yaml: "yaml"
        case .csv: "csv"
        case .html: "html"
        case .xml: "xml"
        case .swift: "swift"
        case .python: "py"
        case .javascript: "js"
        case .typescript: "ts"
        case .sql: "sql"
        case .shell: "sh"
        case .css: "css"
        case .plainText: "txt"
        }
    }

    var systemImage: String {
        switch self {
        case .markdown: "text.document.fill"
        case .json, .yaml, .xml: "curlybraces.square.fill"
        case .csv: "tablecells.fill"
        case .html: "globe"
        case .swift: "swift"
        case .python: "chevron.left.forwardslash.chevron.right"
        case .javascript, .typescript: "j.square.fill"
        case .sql: "cylinder.fill"
        case .shell: "terminal.fill"
        case .css: "paintbrush.fill"
        case .plainText: "doc.text.fill"
        }
    }
}
