import Foundation

struct CaptureRelationMatch: Identifiable, Sendable {
    let item: CaptureItem
    let score: Int
    let reasons: [String]

    var id: CaptureItem.ID { item.id }
}

enum CaptureRelationEngine {
    private struct Profile {
        let title: Set<String>
        let content: Set<String>
        var all: Set<String> { title.union(content) }
    }

    private static let genericTags: Set<String> = [
        "文字", "图片", "截图", "网页", "文件", "账号", "文档", "markdown", "纯文本", "自动整理"
    ]

    private static let stopTokens: Set<String> = [
        "the", "and", "for", "with", "from", "this", "that", "into", "your", "you", "are", "was", "were",
        "aligned", "mathrm", "mathbf", "operatorname", "begin", "end", "right", "left", "text", "frac", "sum",
        "section", "subsection", "itemize", "enumerate", "label", "includegraphics", "linewidth", "centering",
        "一个", "这个", "那个", "当前", "现在", "需要", "可以", "进行", "已经", "没有", "同时", "然后", "比如",
        "最好", "实现", "支持", "内容", "信息", "文档", "文件", "网页", "记录", "相关", "界面", "方式", "问题"
    ]

    static func matches(
        target: CaptureItem,
        candidates: [CaptureItem],
        limit: Int = 4
    ) -> [CaptureRelationMatch] {
        let available = candidates.filter { !$0.isDeleted && $0.id != target.id }
        guard !available.isEmpty, limit > 0 else { return [] }

        let allItems = [target] + available
        let profiles = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, profile(for: $0)) })
        var documentFrequency: [String: Int] = [:]
        for profile in profiles.values {
            for token in profile.all { documentFrequency[token, default: 0] += 1 }
        }
        let rarityLimit = max(2, Int(ceil(Double(allItems.count) * 0.34)))

        return available.compactMap { candidate -> CaptureRelationMatch? in
            guard let targetProfile = profiles[target.id], let candidateProfile = profiles[candidate.id] else { return nil }
            var score = 0
            var reasons: [String] = []
            var hasRealRelation = false

            if let compositionID = target.compositionID, compositionID == candidate.compositionID {
                score += 120
                reasons.append("同一组合")
                hasRealRelation = true
            }

            let sharedTags = meaningfulTags(target.tags).intersection(meaningfulTags(candidate.tags)).sorted()
            if !sharedTags.isEmpty {
                score += min(75, sharedTags.count * 25)
                reasons.append("共同标签：\(sharedTags.prefix(2).joined(separator: "、"))")
                hasRealRelation = true
            }

            if let targetDomain = normalizedDomain(for: target), targetDomain == normalizedDomain(for: candidate) {
                score += 30
                reasons.append("同站点：\(targetDomain)")
                hasRealRelation = true
            }

            if let platform = target.platform?.trimmingCharacters(in: .whitespacesAndNewlines),
               !platform.isEmpty,
               platform.caseInsensitiveCompare(candidate.platform ?? "") == .orderedSame {
                score += 28
                reasons.append("同平台：\(platform)")
                hasRealRelation = true
            }

            let rare: (String) -> Bool = { (documentFrequency[$0] ?? 0) <= rarityLimit }
            let sharedTitle = targetProfile.title.intersection(candidateProfile.title).filter(rare)
            let crossTitle = targetProfile.title.intersection(candidateProfile.content)
                .union(candidateProfile.title.intersection(targetProfile.content))
                .filter(rare)
            let sharedContent = targetProfile.content.intersection(candidateProfile.content).filter(rare)
            let topicTokens = sharedTitle.union(crossTitle).union(sharedContent).sorted { left, right in
                let leftFrequency = documentFrequency[left] ?? 0
                let rightFrequency = documentFrequency[right] ?? 0
                if leftFrequency == rightFrequency { return left.count > right.count }
                return leftFrequency < rightFrequency
            }

            if !sharedTitle.isEmpty {
                score += min(48, sharedTitle.count * 16)
                hasRealRelation = true
            }
            if !crossTitle.isEmpty {
                score += min(32, crossTitle.count * 8)
                hasRealRelation = true
            }
            if sharedContent.count >= 2 {
                score += min(28, sharedContent.count * 4)
                hasRealRelation = true
            }
            if hasRealRelation, !topicTokens.isEmpty {
                let displayTopics = topicTokens.filter(isDisplayableTopic)
                reasons.append(displayTopics.isEmpty
                    ? "正文主题高度重合"
                    : "共同主题：\(displayTopics.prefix(3).joined(separator: "、"))")
            }

            guard hasRealRelation else { return nil }
            if target.collection != nil, target.collection == candidate.collection { score += 3 }
            if target.sourceApplication != nil, target.sourceApplication == candidate.sourceApplication { score += 2 }
            let dayDistance = abs(target.createdAt.timeIntervalSince(candidate.createdAt))
            if dayDistance <= 86_400 { score += 2 }

            return CaptureRelationMatch(item: candidate, score: score, reasons: Array(reasons.prefix(3)))
        }
        .sorted {
            if $0.score == $1.score { return $0.item.createdAt > $1.item.createdAt }
            return $0.score > $1.score
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func profile(for item: CaptureItem) -> Profile {
        let title = tokens(in: item.title + " " + item.tags.joined(separator: " "))
        let body = String(item.body.prefix(1_600))
        let content = tokens(in: [item.summary, body, item.userNote ?? "", item.platform ?? "", item.domain ?? ""]
            .joined(separator: " "))
        return Profile(title: title, content: content)
    }

    private static func meaningfulTags(_ tags: [String]) -> Set<String> {
        Set(tags.compactMap { tag in
            let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard clean.count >= 2, !genericTags.contains(clean) else { return nil }
            return clean
        })
    }

    private static func normalizedDomain(for item: CaptureItem) -> String? {
        let raw = item.webRootDomain ?? item.domain ?? URL(string: item.body)?.host(percentEncoded: false)
        guard let raw else { return nil }
        let clean = raw.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return clean.hasPrefix("www.") ? String(clean.dropFirst(4)) : clean
    }

    private static func tokens(in text: String) -> Set<String> {
        let value = text.lowercased()
        guard let expression = try? NSRegularExpression(pattern: "[\\p{L}\\p{N}]+") else { return [] }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        var output = Set<String>()

        for match in expression.matches(in: value, range: range) {
            guard let swiftRange = Range(match.range, in: value) else { continue }
            let word = String(value[swiftRange])
            guard !word.allSatisfy(\.isNumber), !stopTokens.contains(word) else { continue }

            if word.unicodeScalars.contains(where: isHan) {
                let characters = Array(word)
                if (2...12).contains(characters.count), !stopTokens.contains(word) { output.insert(word) }
                for width in [2] where characters.count >= width {
                    for start in 0...(characters.count - width) {
                        let token = String(characters[start..<(start + width)])
                        if isUsefulHanToken(token) { output.insert(token) }
                    }
                }
            } else if word.count >= 3, !stopTokens.contains(word) {
                output.insert(word)
            }
        }
        return output
    }

    private static func isHan(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF: true
        default: false
        }
    }

    private static func isUsefulHanToken(_ token: String) -> Bool {
        guard !stopTokens.contains(token), let first = token.first, let last = token.last else { return false }
        let weakBoundary = CharacterSet(charactersIn: "的一了是在和与及对从将为中上下内外后前之其而或把被")
        let firstWeak = first.unicodeScalars.allSatisfy(weakBoundary.contains)
        let lastWeak = last.unicodeScalars.allSatisfy(weakBoundary.contains)
        return !firstWeak && !lastWeak
    }

    private static func isDisplayableTopic(_ token: String) -> Bool {
        guard token.count >= 2, !stopTokens.contains(token) else { return false }
        if token.unicodeScalars.contains(where: isHan) { return isUsefulHanToken(token) }
        return token.count >= 4
    }
}
