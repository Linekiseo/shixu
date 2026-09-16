import AppKit
import Combine
import Foundation

@MainActor
final class CaptureStore: ObservableObject {
    static let shared = CaptureStore()
    static let recordDragPrefix = "xushi-record://"

    @Published var items: [CaptureItem]
    @Published private var navigation = CaptureNavigation(destination: .category(.inbox), selectedItemID: nil)
    @Published var clipboardCandidate: ClipboardCandidate?
    @Published var systemSignals: [SystemSignal] = []
    @Published var lastConfirmation: String?
    @Published var focusRequest: CaptureFocusRequest?
    private let persistenceEnabled: Bool

    private init() {
        persistenceEnabled = true
        let migration = BundledSampleMigration.removeExamples(
            from: PersistenceService.loadItems() ?? []
        )
        for removedItem in migration.removed {
            if let key = removedItem.secretKey {
                KeychainService.delete(key: key)
            }
        }
        items = migration.kept
        Self.migratePreviouslyCapturedAPIKeys(items: &items)
        Self.organize(items: &items)
        Self.backfillSourceApplications(items: &items)
        Self.backfillContentFingerprints(items: &items)
        Self.markInvalidAccessWallArchives(items: &items)
        navigation = CaptureNavigation(destination: .category(.inbox), selectedItemID: items.first?.id)
        collapseLegacyLLMCompositions()
        PersistenceService.saveItems(items)
        Task { @MainActor [weak self] in
            await Task.yield()
            self?.resumeInterruptedWebArchives()
        }
    }

    init(testItems: [CaptureItem]) {
        persistenceEnabled = false
        items = testItems
        Self.organize(items: &items)
        Self.backfillSourceApplications(items: &items)
        Self.backfillContentFingerprints(items: &items)
        navigation = CaptureNavigation(destination: .category(.inbox), selectedItemID: items.first?.id)
        collapseLegacyLLMCompositions()
    }

    var destination: CaptureDestination { navigation.destination }

    var selectedItemID: CaptureItem.ID? {
        get { navigation.selectedItemID }
        set {
            guard navigation.selectedItemID != newValue else { return }
            navigation = CaptureNavigation(destination: navigation.destination, selectedItemID: newValue)
        }
    }

    var category: SidebarCategory { destination.category }

    var selectedCollection: String? { destination.collection }

    var selectedItem: CaptureItem? {
        guard let selectedItemID else { return nil }
        return items.first(where: { $0.id == selectedItemID })
    }

    var visibleItems: [CaptureItem] {
        items
            .filter(destination.includes)
            .sorted { $0.createdAt > $1.createdAt }
    }

    var availableCollections: [String] {
        let preferred = ["灵感", "阅读", "行动", "资料", "账号", "随想"]
        let existing = Set(items.compactMap(\.collection).filter { !$0.isEmpty })
        return preferred.filter(existing.contains) + existing.subtracting(preferred).sorted()
    }

    var compositionGroups: [CaptureCompositionGroup] {
        CaptureCompositionGroup.groups(from: items)
    }

    var activeTitle: String {
        selectedCollection ?? category.title
    }

    func search(
        _ query: String,
        kind: SearchKindScope = .all,
        dateScope: SearchDateScope = .all
    ) -> [CaptureItem] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let terms = normalized.split(separator: " ")
        return items
            .filter { !$0.isDeleted }
            .filter(kind.includes)
            .filter { dateScope.includes($0.createdAt) }
            .filter { item in
                guard !terms.isEmpty else { return true }
                let searchable = [
                    item.title, item.body, item.summary, item.source, item.sourceApplication ?? "",
                    item.username ?? "", item.platform ?? "", item.domain ?? "", item.loginURL ?? "", item.fileName ?? "",
                    item.apiBaseURL ?? "", item.credentialType?.title ?? "",
                    item.fileExtension ?? "", item.originalLocation ?? "", item.collection ?? "",
                    item.userNote ?? "", item.compositionTitle ?? "", item.compositionKind?.title ?? ""
                ] + item.tags
                let haystack = searchable.joined(separator: " ").lowercased()
                return terms.allSatisfy { haystack.contains($0) }
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func search(_ query: String, using plan: AISearchPlan) -> [CaptureItem] {
        let plannedTerms = plan.keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        let fallbackTerms = query.lowercased().split(whereSeparator: { $0.isWhitespace || $0.isPunctuation }).map(String.init)
        let terms = plannedTerms.isEmpty ? fallbackTerms : plannedTerms
        let startDate = plan.boundaryDate(plan.startDate, endOfDay: false)
        let endDate = plan.boundaryDate(plan.endDate, endOfDay: true)
        let requestedCollection = plan.collection?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return items
            .filter { !$0.isDeleted }
            .filter(plan.kindScope.includes)
            .filter { item in
                if let startDate, item.createdAt < startDate { return false }
                if let endDate, item.createdAt >= endDate { return false }
                if startDate == nil && endDate == nil && !plan.fallbackDateScope.includes(item.createdAt) { return false }
                if let requestedCollection, !requestedCollection.isEmpty,
                   item.collection?.lowercased() != requestedCollection { return false }
                return true
            }
            .map { item -> (CaptureItem, Int) in
                let title = item.title.lowercased()
                let summary = item.summary.lowercased()
                let body = item.body.lowercased()
                let tags = item.tags.joined(separator: " ").lowercased()
                let metadata = [
                    item.source, item.sourceApplication ?? "", item.platform ?? "", item.domain ?? "", item.loginURL ?? "",
                    item.apiBaseURL ?? "", item.fileName ?? "", item.fileExtension ?? "",
                    item.originalLocation ?? "", item.collection ?? "", item.userNote ?? "",
                    item.compositionTitle ?? ""
                ].joined(separator: " ").lowercased()
                let score = terms.reduce(into: 0) { score, term in
                    if title.contains(term) { score += 9 }
                    if tags.contains(term) { score += 7 }
                    if summary.contains(term) { score += 5 }
                    if metadata.contains(term) { score += 4 }
                    if body.contains(term) { score += 2 }
                }
                return (item, score)
            }
            .filter { terms.isEmpty || $0.1 > 0 }
            .sorted {
                if $0.1 == $1.1 { return $0.0.createdAt > $1.0.createdAt }
                return $0.1 > $1.1
            }
            .map(\.0)
    }

    func capture(
        text: String,
        forcedKind: CaptureKind? = nil,
        source: String = AppBrand.displayName,
        sourceApplication: String? = nil,
        silent: Bool = false
    ) {
        let detected = ContentDetector.detect(text: text, forcedKind: forcedKind)
        let storedBody = detected.textFormat == nil ? detected.body : text
        if let duplicate = duplicateItem(for: detected, storedBody: storedBody) {
            handleDuplicate(duplicate, silent: silent)
            return
        }

        let id = UUID()
        let secretKey = detected.kind == .credential && detected.password != nil ? id.uuidString : nil
        let loginURL = detected.credentialType == .account ? Self.firstURL(in: text) : nil
        let apiBaseURL = detected.credentialType == .apiKey ? detected.apiBaseURL : nil
        let domain = detected.kind == .web
            ? URL(string: detected.body)?.host(percentEncoded: false)
            : (apiBaseURL ?? loginURL).flatMap { URL(string: $0)?.host(percentEncoded: false) }
        let platform = detected.kind == .credential
            ? (detected.platform ?? CredentialPlatformCatalog.infer(title: detected.title, domain: domain, loginURL: loginURL))
            : nil
        if let password = detected.password, let secretKey {
            KeychainService.save(secret: password, key: secretKey)
        }

        let generatedFileName = detected.textFormat.map {
            TextFormatDetector.fileName(title: detected.title, format: $0)
        }
        let generatedPath = generatedFileName.flatMap {
            PersistenceService.saveTextContent(storedBody, itemID: id, fileName: $0)
        }

        let item = CaptureItem(
            id: id,
            kind: detected.kind,
            title: detected.title,
            body: storedBody,
            source: source,
            sourceApplication: sourceApplication,
            tags: detected.tags,
            summary: detected.summary,
            textFormat: detected.textFormat,
            attachmentPath: generatedPath,
            fileName: generatedFileName,
            username: detected.username,
            secretKey: secretKey,
            credentialType: detected.credentialType,
            platform: platform,
            domain: domain,
            webRootDomain: detected.kind == .web
                ? URL(string: detected.body).flatMap(WebsiteIdentity.rootDomain(for:))
                : nil,
            webArchiveState: detected.kind == .web ? .queued : nil,
            webArchiveMessage: detected.kind == .web ? "等待创建本地离线存档" : nil,
            loginURL: loginURL,
            apiBaseURL: apiBaseURL,
            fileSize: detected.textFormat == nil ? nil : Int64(storedBody.utf8.count),
            fileExtension: detected.textFormat?.fileExtension.uppercased(),
            contentFingerprint: detected.kind == .credential
                ? nil
                : CaptureContentIdentity.textFingerprint(storedBody),
            collection: detected.textFormat == nil ? Self.suggestedCollection(for: detected.kind, tags: detected.tags) : "资料",
            organizationReason: detected.textFormat.map { "识别为\($0.title)，自动生成 .\($0.fileExtension) 文件" }
                ?? Self.organizationReason(for: detected.kind),
            securityLevel: detected.kind == .credential ? .sensitive : .standard,
            needsReview: false
        )
        insert(item, silent: silent)
    }

    func captureCredential(
        platform: String,
        username: String,
        password: String,
        loginURL: String,
        source: String = "手动录入"
    ) {
        let cleanPlatform = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLoginURL = Self.normalizedOptionalURL(loginURL)
        let domain = cleanLoginURL.flatMap { URL(string: $0)?.host(percentEncoded: false) }
        let id = UUID()
        let secretKey = password.isEmpty ? nil : id.uuidString
        if let secretKey { KeychainService.save(secret: password, key: secretKey) }

        let platformName = cleanPlatform.isEmpty
            ? CredentialPlatformCatalog.infer(title: "", domain: domain, loginURL: cleanLoginURL) ?? "其他账号"
            : cleanPlatform
        let item = CaptureItem(
            id: id,
            kind: .credential,
            title: "\(platformName) · 账号",
            body: "账号：\(cleanUsername)",
            source: source,
            tags: ["账号", platformName, cleanLoginURL == nil ? "本机" : "网页绑定"],
            summary: cleanLoginURL == nil
                ? "\(platformName) 账号已保存，密码仅进入 macOS 钥匙串。"
                : "\(platformName) 账号已关联登录网页，密码仅进入 macOS 钥匙串。",
            username: cleanUsername,
            secretKey: secretKey,
            credentialType: .account,
            platform: platformName,
            domain: domain,
            loginURL: cleanLoginURL,
            collection: "账号",
            organizationReason: "按平台归入账号保险箱",
            securityLevel: .sensitive,
            needsReview: false
        )
        insert(item)
    }

    func updateCredential(
        id: CaptureItem.ID,
        platform: String,
        username: String,
        password: String,
        loginURL: String
    ) {
        guard let index = items.firstIndex(where: { $0.id == id && $0.kind == .credential }) else { return }
        let cleanPlatform = platform.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLoginURL = Self.normalizedOptionalURL(loginURL)
        let domain = cleanLoginURL.flatMap { URL(string: $0)?.host(percentEncoded: false) }
        let previousPlatform = items[index].platform

        if !password.isEmpty {
            let key = items[index].secretKey ?? id.uuidString
            KeychainService.save(secret: password, key: key)
            items[index].secretKey = key
        }
        items[index].platform = cleanPlatform
        items[index].username = cleanUsername
        items[index].credentialType = .account
        items[index].loginURL = cleanLoginURL
        items[index].apiBaseURL = nil
        items[index].domain = domain
        items[index].title = "\(cleanPlatform) · 账号"
        items[index].body = "账号：\(cleanUsername)"
        items[index].summary = cleanLoginURL == nil
            ? "\(cleanPlatform) 账号已保存，密码仅进入 macOS 钥匙串。"
            : "\(cleanPlatform) 账号已关联登录网页，密码仅进入 macOS 钥匙串。"
        items[index].tags = Array(Set(items[index].tags.filter {
            $0 != "网页绑定" && $0 != "本机" && $0 != previousPlatform
        } + ["账号", cleanPlatform, cleanLoginURL == nil ? "本机" : "网页绑定"])).sorted()
        persist()
        showConfirmation("账号平台信息已更新")
    }

    @discardableResult
    func captureAPIKey(
        provider: String,
        keyLabel: String,
        apiKey: String,
        baseURL: String,
        source: String = "手动录入"
    ) -> CaptureItem.ID {
        let cleanProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLabel = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBaseURL = Self.normalizedOptionalURL(baseURL)
        let id = UUID()
        let secretKey = apiKey.isEmpty ? nil : id.uuidString
        if let secretKey { KeychainService.save(secret: apiKey, key: secretKey) }
        let providerName = cleanProvider.isEmpty ? "OpenAI 兼容 / 待确认" : cleanProvider
        let label = cleanLabel.isEmpty ? "默认密钥" : cleanLabel
        let domain = cleanBaseURL.flatMap { URL(string: $0)?.host(percentEncoded: false) }

        let item = CaptureItem(
            id: id,
            kind: .credential,
            title: "\(providerName) · API 密钥",
            body: "API 密钥已安全保存",
            source: source,
            tags: ["API密钥", providerName, "受保护"],
            summary: cleanBaseURL == nil
                ? "LLM API 密钥已保存到 macOS 钥匙串，Base URL 待配置。"
                : "LLM API 密钥已保存到 macOS 钥匙串，并已配置 API Base URL。",
            username: label,
            secretKey: secretKey,
            credentialType: .apiKey,
            platform: providerName,
            domain: domain,
            apiBaseURL: cleanBaseURL,
            collection: "账号",
            organizationReason: "识别为 LLM API 密钥，归入本机保险箱",
            securityLevel: .sensitive,
            needsReview: cleanBaseURL == nil
        )
        insert(item)
        return id
    }

    func updateAPIKey(
        id: CaptureItem.ID,
        provider: String,
        keyLabel: String,
        apiKey: String,
        baseURL: String
    ) {
        guard let index = items.firstIndex(where: { $0.id == id && $0.kind == .credential }) else { return }
        let cleanProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerName = cleanProvider.isEmpty ? "OpenAI 兼容 / 待确认" : cleanProvider
        let cleanLabel = keyLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBaseURL = Self.normalizedOptionalURL(baseURL)
        let previousPlatform = items[index].platform

        if !apiKey.isEmpty {
            let key = items[index].secretKey ?? id.uuidString
            KeychainService.save(secret: apiKey, key: key)
            items[index].secretKey = key
        }
        items[index].credentialType = .apiKey
        items[index].platform = providerName
        items[index].username = cleanLabel.isEmpty ? "默认密钥" : cleanLabel
        items[index].loginURL = nil
        items[index].apiBaseURL = cleanBaseURL
        items[index].domain = cleanBaseURL.flatMap { URL(string: $0)?.host(percentEncoded: false) }
        items[index].title = "\(providerName) · API 密钥"
        items[index].body = "API 密钥已安全保存"
        items[index].summary = cleanBaseURL == nil
            ? "LLM API 密钥已保存到 macOS 钥匙串，Base URL 待配置。"
            : "LLM API 密钥已保存到 macOS 钥匙串，并已配置 API Base URL。"
        items[index].tags = Array(Set(items[index].tags.filter {
            $0 != "账号" && $0 != "网页绑定" && $0 != "本机" && $0 != previousPlatform
        } + ["API密钥", providerName, "受保护"])).sorted()
        items[index].organizationReason = "识别为 LLM API 密钥，归入本机保险箱"
        items[index].needsReview = cleanBaseURL == nil
        persist()
        showConfirmation("API 密钥配置已更新")
    }

    func capture(
        fileURL: URL,
        source: String = "拖入文件",
        sourceApplication: String? = nil,
        silent: Bool = false
    ) {
        let existingIndex = items.firstIndex { $0.originalLocation == fileURL.path }
        if let existingIndex, items[existingIndex].isDeleted {
            handleDuplicate(items[existingIndex], silent: silent)
            return
        }
        let id = existingIndex.map { items[$0].id } ?? UUID()
        let kind = ContentDetector.kind(for: fileURL)
        let mode = FileStorageMode(rawValue: UserDefaults.standard.string(forKey: "fileStorageMode") ?? "") ?? .linked
        let reference = FileReferenceService.register(url: fileURL, itemID: id, mode: mode)
        let fileName = fileURL.lastPathComponent

        if let existingIndex {
            items[existingIndex].createdAt = .now
            items[existingIndex].kind = kind
            items[existingIndex].title = fileName
            items[existingIndex].source = source
            if let sourceApplication { items[existingIndex].sourceApplication = sourceApplication }
            items[existingIndex].fileName = fileName
            items[existingIndex].originalLocation = reference.originalPath
            items[existingIndex].fileSize = reference.fileSize
            items[existingIndex].fileExtension = reference.fileExtension
            items[existingIndex].fileBookmark = reference.bookmark ?? items[existingIndex].fileBookmark
            if let backupPath = reference.backupPath {
                items[existingIndex].backupPath = backupPath
                items[existingIndex].backupOriginalSize = reference.backupOriginalSize
                items[existingIndex].backupCompressedSize = reference.backupCompressedSize
            }
            let hasBackup = items[existingIndex].backupPath != nil
            items[existingIndex].summary = hasBackup
                ? "文件索引已更新；原文件保持在原位置，并保留 LZFSE 无损压缩备份。"
                : "文件索引已更新；\(AppBrand.displayName)仍只引用原文件。"
            persist()
            if !silent {
                selectedItemID = id
                showConfirmation("已刷新文件索引，没有创建重复记录")
            }
            return
        }

        let item = CaptureItem(
            id: id,
            kind: kind,
            title: fileName,
            source: source,
            sourceApplication: sourceApplication,
            tags: kind == .image ? ["图片", "本地引用"] : ["文件", reference.fileExtension, "本地引用"],
            summary: mode == .linked ? "已建立原文件引用；\(AppBrand.displayName)不会创建第二份文件。" : "已建立原文件引用，并创建 LZFSE 无损压缩备份。",
            fileName: fileName,
            originalLocation: reference.originalPath,
            fileSize: reference.fileSize,
            fileExtension: reference.fileExtension,
            fileBookmark: reference.bookmark,
            backupPath: reference.backupPath,
            backupOriginalSize: reference.backupOriginalSize,
            backupCompressedSize: reference.backupCompressedSize,
            collection: kind == .image ? "灵感" : "资料",
            organizationReason: kind == .image ? "根据图片类型自动归入灵感" : "根据文件类型自动归入资料",
            securityLevel: .standard,
            needsReview: false
        )
        insert(item, silent: silent)
    }

    func capture(
        imageData: Data,
        source: String = "剪贴板截图",
        sourceApplication: String? = nil,
        silent: Bool = false
    ) {
        let fingerprint = CaptureContentIdentity.dataFingerprint(imageData)
        if let duplicate = items.first(where: { $0.contentFingerprint == fingerprint }) {
            handleDuplicate(duplicate, silent: silent)
            return
        }
        let id = UUID()
        let path = PersistenceService.saveImageData(imageData, itemID: id)
        let item = CaptureItem(
            id: id,
            kind: .image,
            title: "截图 · \(Date.now.suijiTime)",
            source: source,
            sourceApplication: sourceApplication,
            tags: ["截图", "未整理"],
            summary: "从系统剪贴板保存的截图。",
            attachmentPath: path,
            fileName: "clipboard.png",
            fileSize: Int64(imageData.count),
            fileExtension: "PNG",
            contentFingerprint: fingerprint,
            collection: "灵感",
            organizationReason: "截图自动归入灵感",
            securityLevel: .standard,
            needsReview: false
        )
        insert(item, silent: silent)
    }

    func capture(candidate: ClipboardCandidate, source: String = "剪贴板", silent: Bool = false) {
        if let imageData = candidate.imageData {
            capture(imageData: imageData, source: source, sourceApplication: candidate.sourceApplication, silent: silent)
        } else if let fileURL = candidate.fileURL {
            capture(fileURL: fileURL, source: source, sourceApplication: candidate.sourceApplication, silent: silent)
        } else if let text = candidate.text {
            capture(text: text, source: source, sourceApplication: candidate.sourceApplication, silent: silent)
        }
        clipboardCandidate = nil
    }

    func receive(candidate: ClipboardCandidate) {
        var signal = SystemSignal(
            source: .clipboard,
            kind: candidate.kind,
            title: candidate.kind == .credential
                ? (candidate.text.flatMap { LLMAPIKeyDetector.detect(in: $0) } == nil ? "检测到敏感账号信息" : "检测到 LLM API 密钥")
                : "检测到新的\(candidate.kind.title)",
            detail: candidate.displayText,
            sourceApplication: candidate.sourceApplication,
            candidate: candidate
        )
        let duplicate = isDuplicate(candidate)
        if duplicate { signal.state = .ignored }
        systemSignals.insert(signal, at: 0)
        if systemSignals.count > 100 { systemSignals.removeLast(systemSignals.count - 100) }

        guard !duplicate else { return }

        let ambientEnabled = UserDefaults.standard.bool(forKey: "ambientCaptureEnabled")
        let clipboardEnabled = UserDefaults.standard.bool(forKey: "autoCaptureClipboard")
        if ambientEnabled && clipboardEnabled && shouldAutoCapture(candidate) {
            capture(candidate: candidate, source: "无感记录 · \(candidate.sourceApplication ?? "剪贴板")", silent: true)
            systemSignals[0].state = .captured
        } else {
            clipboardCandidate = candidate
        }
    }

    func receiveDetectedFile(_ url: URL) {
        let signal = SystemSignal(
            source: .watchedFolder,
            kind: ContentDetector.kind(for: url),
            title: url.lastPathComponent,
            detail: url.deletingLastPathComponent().path,
            fileURL: url
        )
        systemSignals.insert(signal, at: 0)
        if UserDefaults.standard.bool(forKey: "ambientCaptureEnabled") && UserDefaults.standard.bool(forKey: "autoIndexWatchedFolders") {
            capture(fileURL: url, source: "无感记录 · 监测文件夹", silent: true)
            systemSignals[0].state = .captured
        }
    }

    func capture(signalID: SystemSignal.ID) {
        guard let index = systemSignals.firstIndex(where: { $0.id == signalID }) else { return }
        let signal = systemSignals[index]
        if let candidate = signal.candidate {
            capture(candidate: candidate, source: signal.source.title)
        } else if let fileURL = signal.fileURL {
            capture(fileURL: fileURL, source: signal.source.title)
        }
        systemSignals[index].state = .captured
    }

    func ignore(signalID: SystemSignal.ID) {
        guard let index = systemSignals.firstIndex(where: { $0.id == signalID }) else { return }
        systemSignals[index].state = .ignored
        if clipboardCandidate == systemSignals[index].candidate { clipboardCandidate = nil }
    }

    func importCurrentClipboard() {
        ClipboardMonitor.shared.poll(store: self, force: true)
        if let candidate = clipboardCandidate {
            capture(candidate: candidate)
        }
    }

    func synchronizeGeneratedTextFiles() {
        var updatedItems = items
        var changed = false
        for index in updatedItems.indices {
            guard let format = updatedItems[index].textFormat,
                  let fileName = updatedItems[index].fileName else { continue }

            if let path = updatedItems[index].attachmentPath,
               let url = PersistenceService.resolveAttachment(path),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                if content != updatedItems[index].body {
                    updatedItems[index].body = content
                    updatedItems[index].fileSize = Int64(content.utf8.count)
                    updatedItems[index].summary = "\(format.title) 文件的外部修改已同步到全文搜索。"
                    changed = true
                }
            } else if let path = PersistenceService.saveTextContent(
                updatedItems[index].body,
                itemID: updatedItems[index].id,
                fileName: fileName
            ) {
                updatedItems[index].attachmentPath = path
                updatedItems[index].fileSize = Int64(updatedItems[index].body.utf8.count)
                changed = true
            }
        }
        if changed {
            items = updatedItems
            persist()
        }
    }

    func toggleFavorite(_ id: CaptureItem.ID) {
        mutate(id) { $0.isFavorite.toggle() }
    }

    func moveToTrash(_ id: CaptureItem.ID) {
        WebArchiveCaptureService.shared.cancel(itemID: id)
        if items.first(where: { $0.id == id })?.compositionID != nil {
            removeFromComposition(id)
        }
        mutate(id) { $0.isDeleted = true }
        if selectedItemID == id { selectedItemID = visibleItems.first?.id }
    }

    func restore(_ id: CaptureItem.ID) {
        restore(Set([id]))
    }

    func restore(_ ids: Set<CaptureItem.ID>) {
        guard !ids.isEmpty else { return }
        var restoredCount = 0
        for index in items.indices where ids.contains(items[index].id) && items[index].isDeleted {
            items[index].isDeleted = false
            restoredCount += 1
        }
        guard restoredCount > 0 else { return }
        persist()
        selectedItemID = category == .trash
            ? visibleItems.first?.id
            : items.first(where: { ids.contains($0.id) })?.id ?? selectedItemID
        showConfirmation(restoredCount == 1 ? "已恢复 1 条记录" : "已批量恢复 \(restoredCount) 条记录")
    }

    func deletePermanently(_ id: CaptureItem.ID) {
        deletePermanently(Set([id]))
    }

    func deletePermanently(_ ids: Set<CaptureItem.ID>) {
        guard !ids.isEmpty else { return }
        let targets = items.filter { ids.contains($0.id) }
        guard !targets.isEmpty else { return }

        for item in targets {
            WebArchiveCaptureService.shared.cancel(itemID: item.id)
            deleteResources(for: item)
        }
        items.removeAll { ids.contains($0.id) }
        persist()
        if selectedItemID.map(ids.contains) == true { selectedItemID = visibleItems.first?.id }
        showConfirmation(targets.count == 1 ? "已永久删除 1 条记录" : "已批量永久删除 \(targets.count) 条记录")
    }

    func updateTags(_ tags: [String], for id: CaptureItem.ID) {
        mutate(id) { $0.tags = tags }
    }

    func removeTag(_ tag: String, from id: CaptureItem.ID) {
        mutate(id) { $0.tags.removeAll(where: { $0 == tag }) }
    }

    func assignCollection(_ collection: String?, to id: CaptureItem.ID) {
        let clean = collection?.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(id) {
            $0.collection = clean?.isEmpty == false ? clean : nil
            $0.organizationReason = clean?.isEmpty == false ? "由你整理到此集合" : "等待整理"
        }
        showConfirmation(clean?.isEmpty == false ? "已整理到「\(clean!)」" : "已移出集合")
    }

    func updateNote(_ note: String, for id: CaptureItem.ID) {
        let clean = note.trimmingCharacters(in: .whitespacesAndNewlines)
        mutate(id) { $0.userNote = clean.isEmpty ? nil : clean }
    }

    func selectCategory(_ category: SidebarCategory, selecting itemID: CaptureItem.ID? = nil) {
        navigate(to: .category(category), selecting: itemID)
    }

    func revealInAll(_ itemID: CaptureItem.ID) {
        navigate(to: .category(.all), selecting: itemID)
        focusRequest = CaptureFocusRequest(itemID: itemID)
    }

    func selectCollection(_ collection: String) {
        navigate(to: .collection(collection))
    }

    func count(in collection: String) -> Int {
        items.filter { !$0.isDeleted && $0.collection == collection }.count
    }

    func createCompressedBackup(for id: CaptureItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let url = attachmentURL(for: items[index]),
              let backup = LZFSEBackupService.createBackup(from: url, itemID: id) else { return }
        items[index].backupPath = backup.relativePath
        items[index].backupOriginalSize = backup.originalSize
        items[index].backupCompressedSize = backup.compressedSize
        if !items[index].tags.contains("压缩备份") { items[index].tags.append("压缩备份") }
        items[index].summary = "原文件保持在原位置，并已创建 LZFSE 无损压缩备份。"
        persist()
        showConfirmation("已创建 LZFSE 无损压缩备份")
    }

    func relatedItems(to item: CaptureItem, limit: Int = 4) -> [CaptureItem] {
        relatedMatches(to: item, limit: limit).map(\.item)
    }

    func relatedMatches(to item: CaptureItem, limit: Int = 4) -> [CaptureRelationMatch] {
        CaptureRelationEngine.matches(target: item, candidates: items, limit: limit)
    }

    func compositionMembers(for item: CaptureItem) -> [CaptureItem] {
        guard let compositionID = item.compositionID else { return [] }
        return items
            .filter { !$0.isDeleted && $0.compositionID == compositionID }
            .sorted {
                let left = $0.compositionOrder ?? Int.max
                let right = $1.compositionOrder ?? Int.max
                if left == right { return $0.createdAt < $1.createdAt }
                return left < right
            }
    }

    func webArchiveURL(for item: CaptureItem) -> URL? {
        guard let relativePath = item.webArchivePath else { return nil }
        return WebArchiveStorageService.restoredURL(relativePath: relativePath)
    }

    func requestWebArchive(for itemID: CaptureItem.ID) {
        guard persistenceEnabled,
              let index = items.firstIndex(where: { $0.id == itemID && !$0.isDeleted && $0.kind == .web }),
              let url = URL(string: items[index].body) else { return }
        items[index].webRootDomain = WebsiteIdentity.rootDomain(for: url)
        items[index].webArchiveState = .capturing
        items[index].webArchiveMessage = "正在使用站点会话加载并保存完整网页"
        persist()

        WebArchiveCaptureService.shared.enqueue(itemID: itemID, url: url) { [weak self] result in
            self?.handleWebArchiveCapture(result, itemID: itemID)
        }
    }

    func storeAuthenticatedWebArchive(
        _ data: Data,
        for itemID: CaptureItem.ID,
        pageTitle: String?,
        finalURL: URL?
    ) {
        guard let index = items.firstIndex(where: { $0.id == itemID && $0.kind == .web }) else { return }
        items[index].webArchiveState = .capturing
        items[index].webArchiveMessage = "正在压缩登录后的网页存档"
        persist()
        saveWebArchive(data, itemID: itemID, pageTitle: pageTitle, finalURL: finalURL, retrySiteAfterward: true)
    }

    private func handleWebArchiveCapture(_ result: WebArchiveCaptureResult, itemID: CaptureItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        switch result {
        case let .archived(data, title, finalURL):
            saveWebArchive(data, itemID: itemID, pageTitle: title, finalURL: finalURL, retrySiteAfterward: false)
        case let .loginRequired(message):
            items[index].webArchiveState = .loginRequired
            items[index].webArchiveMessage = message
            persist()
        case let .failed(message):
            items[index].webArchiveState = .failed
            items[index].webArchiveMessage = message
            persist()
        }
    }

    private func saveWebArchive(
        _ data: Data,
        itemID: CaptureItem.ID,
        pageTitle: String?,
        finalURL: URL?,
        retrySiteAfterward: Bool
    ) {
        Task { [weak self] in
            let stored = await Task.detached(priority: .utility) {
                WebArchiveStorageService.store(data, itemID: itemID)
            }.value
            guard let self, let index = self.items.firstIndex(where: { $0.id == itemID }) else { return }
            guard let stored else {
                self.items[index].webArchiveState = .failed
                self.items[index].webArchiveMessage = "网页已读取，但压缩存储失败"
                self.persist()
                return
            }
            self.items[index].webArchiveState = .archived
            self.items[index].webArchivePath = stored.relativePath
            self.items[index].webArchiveCapturedAt = .now
            self.items[index].webArchiveOriginalSize = stored.originalSize
            self.items[index].webArchiveCompressedSize = stored.compressedSize
            self.items[index].webArchiveMessage = "已保留可离线查看的完整网页存档"
            if let finalURL {
                self.items[index].webRootDomain = WebsiteIdentity.rootDomain(for: finalURL)
            }
            let cleanTitle = pageTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let previousTitle = self.items[index].title.lowercased()
            let previousTitleWasAccessWall = previousTitle.contains("找不到页面")
                || previousTitle.contains("not found")
                || previousTitle.contains("private")
                || previousTitle.contains("需要登录")
            if !cleanTitle.isEmpty,
               self.items[index].title == self.items[index].domain
                || self.items[index].title == "网页"
                || previousTitleWasAccessWall {
                self.items[index].title = cleanTitle
            }
            self.persist()
            self.showConfirmation("网页已压缩备份到本机，可离线查看")
            if retrySiteAfterward, let rootDomain = self.items[index].webRootDomain {
                self.retryPendingArchives(forRootDomain: rootDomain, excluding: itemID)
            }
        }
    }

    private func retryPendingArchives(forRootDomain rootDomain: String, excluding itemID: UUID) {
        let candidates = items.filter {
            $0.id != itemID && !$0.isDeleted && $0.kind == .web
                && $0.webRootDomain == rootDomain
                && ($0.webArchiveState == .loginRequired || $0.webArchiveState == .failed)
        }
        candidates.forEach { requestWebArchive(for: $0.id) }
    }

    private func resumeInterruptedWebArchives() {
        let interrupted = items.filter {
            !$0.isDeleted && $0.kind == .web
                && ($0.webArchiveState == .queued || $0.webArchiveState == .capturing)
        }
        interrupted.forEach { requestWebArchive(for: $0.id) }
    }

    @discardableResult
    func handleDroppedText(_ payload: String, onto targetID: CaptureItem.ID) -> Bool {
        let clean = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.hasPrefix(Self.recordDragPrefix),
           let sourceID = UUID(uuidString: String(clean.dropFirst(Self.recordDragPrefix.count))) {
            return combine(sourceID, onto: targetID)
        }

        if let detected = LLMAPIKeyDetector.detect(in: clean),
           let target = items.first(where: { $0.id == targetID }),
           let baseURL = Self.URLString(for: target) {
            let provider = detected.provider
                ?? LLMProviderCatalog.preset(forBaseURL: baseURL)?.name
                ?? "OpenAI 兼容 / 待确认"
            let apiID = captureAPIKey(
                provider: provider,
                keyLabel: detected.keyLabel,
                apiKey: detected.key,
                baseURL: detected.baseURL ?? baseURL,
                source: "拖拽组合"
            )
            let combined = combine(apiID, onto: targetID)
            if combined { consumeClipboardPayload(clean) }
            return combined
        }

        if LLMAPIKeyDetector.detect(in: clean) == nil,
           let url = Self.strictURLString(clean),
           items.first(where: { $0.id == targetID })?.credentialType == .apiKey {
            configureAPIKey(targetID, baseURL: url)
            consumeClipboardPayload(clean)
            showConfirmation("已从拖入内容补全 API Base URL")
            return true
        }
        return false
    }

    @discardableResult
    func handleDroppedURL(_ url: URL, onto targetID: CaptureItem.ID) -> Bool {
        if url.isFileURL { return false }
        return handleDroppedText(url.absoluteString, onto: targetID)
    }

    @discardableResult
    func combine(_ sourceID: CaptureItem.ID, onto targetID: CaptureItem.ID) -> Bool {
        guard sourceID != targetID,
              let source = items.first(where: { $0.id == sourceID && !$0.isDeleted }),
              let target = items.first(where: { $0.id == targetID && !$0.isDeleted }) else { return false }

        if let apiItem = [source, target].first(where: { $0.credentialType == .apiKey }),
           let urlItem = [source, target].first(where: { $0.id != apiItem.id && Self.URLString(for: $0) != nil }),
           let baseURL = Self.URLString(for: urlItem) {
            configureAPIKey(apiItem.id, baseURL: baseURL, persistChange: false)
            absorbURLRecord(urlItem.id, into: apiItem.id)
            persist()
            showConfirmation("URL 已并入 LLM API 配置，原 URL 记录已移除")
            return true
        }

        if let compositionID = target.compositionID {
            return addToComposition(sourceID, in: compositionID)
        }
        if let compositionID = source.compositionID {
            return addToComposition(targetID, in: compositionID)
        }

        let compositionID = UUID()
        for index in items.indices where items[index].id == sourceID || items[index].id == targetID {
            items[index].compositionID = compositionID
        }

        normalizeCompositionOrder(compositionID)
        updateCompositionMetadata(compositionID)
        persist()
        showConfirmation(items.first(where: { $0.compositionID == compositionID })?.compositionKind == .llmAPI
            ? "已组合为 LLM API 配置，并自动补全地址"
            : "已将两条记录组合在一起")
        return true
    }

    /// A group drop adds records to the container; it does not absorb a URL into an arbitrary member.
    /// If the source belongs to another group, keep that group's members together in their saved order.
    @discardableResult
    func addToComposition(
        _ sourceID: CaptureItem.ID,
        in compositionID: UUID,
        before destinationID: CaptureItem.ID? = nil
    ) -> Bool {
        guard let sourceIndex = items.firstIndex(where: { $0.id == sourceID && !$0.isDeleted }) else { return false }
        let existing = orderedCompositionIndices(compositionID)
        guard existing.count > 1 else { return false }
        if let destinationID, !existing.contains(where: { items[$0].id == destinationID }) { return false }

        if items[sourceIndex].compositionID == compositionID {
            if let destinationID {
                moveCompositionMember(sourceID, in: compositionID, before: destinationID)
            }
            return true
        }

        let incoming = items[sourceIndex].compositionID.map(orderedCompositionIndices) ?? [sourceIndex]
        var ordered = existing
        let insertionIndex = destinationID.flatMap { destination in
            existing.firstIndex(where: { items[$0].id == destination })
        } ?? existing.count
        ordered.insert(contentsOf: incoming, at: insertionIndex)

        var updatedItems = items
        for (order, index) in ordered.enumerated() {
            updatedItems[index].compositionID = compositionID
            updatedItems[index].compositionOrder = order
        }
        items = updatedItems
        updateCompositionMetadata(compositionID)
        persist()
        showConfirmation("已加入组合，共 \(ordered.count) 项")
        return true
    }

    func removeFromComposition(_ itemID: CaptureItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }),
              let compositionID = items[index].compositionID else { return }
        items[index].compositionID = nil
        items[index].compositionKind = nil
        items[index].compositionTitle = nil
        items[index].compositionOrder = nil

        let remaining = items.indices.filter { items[$0].compositionID == compositionID }
        if remaining.count <= 1 {
            for remainingIndex in remaining {
                items[remainingIndex].compositionID = nil
                items[remainingIndex].compositionKind = nil
                items[remainingIndex].compositionTitle = nil
                items[remainingIndex].compositionOrder = nil
            }
        } else {
            updateCompositionMetadata(compositionID)
        }
        persist()
        showConfirmation("已从组合中移出")
    }

    func dissolveComposition(_ compositionID: UUID) {
        let memberIndices = items.indices.filter { items[$0].compositionID == compositionID }
        guard !memberIndices.isEmpty else { return }
        for index in memberIndices {
            items[index].compositionID = nil
            items[index].compositionKind = nil
            items[index].compositionTitle = nil
            items[index].compositionOrder = nil
        }
        persist()
        showConfirmation("已解除组合，所有原始记录仍然保留")
    }

    func moveCompositionMember(
        _ itemID: CaptureItem.ID,
        in compositionID: UUID,
        before destinationID: CaptureItem.ID
    ) {
        guard itemID != destinationID else { return }
        var ordered = orderedCompositionIndices(compositionID)
        guard let sourceOffset = ordered.firstIndex(where: { items[$0].id == itemID }),
              let destinationOffset = ordered.firstIndex(where: { items[$0].id == destinationID }) else { return }
        let movingIndex = ordered.remove(at: sourceOffset)
        let insertionOffset = sourceOffset < destinationOffset ? destinationOffset - 1 : destinationOffset
        ordered.insert(movingIndex, at: max(0, insertionOffset))
        applyCompositionOrder(ordered)
        persist()
        showConfirmation("已调整组合顺序")
    }

    func shiftCompositionMember(_ itemID: CaptureItem.ID, in compositionID: UUID, by offset: Int) {
        guard offset != 0 else { return }
        var ordered = orderedCompositionIndices(compositionID)
        guard let sourceOffset = ordered.firstIndex(where: { items[$0].id == itemID }) else { return }
        let destinationOffset = min(max(0, sourceOffset + offset), ordered.count - 1)
        guard destinationOffset != sourceOffset else { return }
        let movingIndex = ordered.remove(at: sourceOffset)
        ordered.insert(movingIndex, at: destinationOffset)
        applyCompositionOrder(ordered)
        persist()
        showConfirmation("已调整组合顺序")
    }

    func setCompositionMemberOrder(_ orderedIDs: [CaptureItem.ID], in compositionID: UUID) {
        let memberIndices = orderedCompositionIndices(compositionID)
        let currentIDs = memberIndices.map { items[$0].id }
        let validIDs = Set(currentIDs)
        var seenIDs = Set<CaptureItem.ID>()
        var normalized = orderedIDs.filter { validIDs.contains($0) && seenIDs.insert($0).inserted }
        normalized.append(contentsOf: currentIDs.filter { !normalized.contains($0) })
        guard normalized != currentIDs else { return }

        let indexByID = Dictionary(uniqueKeysWithValues: memberIndices.map { (items[$0].id, $0) })
        var updatedItems = items
        for (order, id) in normalized.enumerated() {
            guard let itemIndex = indexByID[id] else { continue }
            updatedItems[itemIndex].compositionOrder = order
        }
        items = updatedItems
        persist()
    }

    func secret(for item: CaptureItem) -> String? {
        guard let key = item.secretKey else { return nil }
        return KeychainService.load(key: key)
    }

    private func configureAPIKey(_ id: CaptureItem.ID, baseURL: String, persistChange: Bool = true) {
        guard let index = items.firstIndex(where: { $0.id == id && $0.credentialType == .apiKey }),
              let cleanBaseURL = Self.normalizedOptionalURL(baseURL) else { return }
        let inferredProvider = LLMProviderCatalog.preset(forBaseURL: cleanBaseURL)
        let currentProvider = items[index].platform ?? ""
        if currentProvider.isEmpty || currentProvider == "OpenAI 兼容 / 待确认" {
            if let inferredProvider {
                items[index].platform = inferredProvider.name
                items[index].title = "\(inferredProvider.name) · API 密钥"
                items[index].tags.removeAll { $0 == "OpenAI 兼容 / 待确认" }
                if !items[index].tags.contains(inferredProvider.name) { items[index].tags.append(inferredProvider.name) }
            }
        }
        items[index].apiBaseURL = cleanBaseURL
        items[index].domain = URL(string: cleanBaseURL)?.host(percentEncoded: false)
        items[index].summary = "LLM API 密钥已保存到 macOS 钥匙串，并已通过拖拽配置 API Base URL。"
        items[index].needsReview = false
        if persistChange { persist() }
    }

    private func absorbURLRecord(_ urlItemID: CaptureItem.ID, into apiItemID: CaptureItem.ID) {
        guard let urlIndex = items.firstIndex(where: { $0.id == urlItemID }),
              let apiIndex = items.firstIndex(where: { $0.id == apiItemID }) else { return }
        let urlItem = items[urlIndex]
        WebArchiveCaptureService.shared.cancel(itemID: urlItemID)
        let apiCompositionID = items[apiIndex].compositionID
        let urlCompositionID = urlItem.compositionID
        let mergedCompositionID = apiCompositionID ?? urlCompositionID

        if let mergedCompositionID {
            let groupIDs = Set([apiCompositionID, urlCompositionID].compactMap { $0 })
            for index in items.indices where items[index].id != urlItemID
                && (items[index].id == apiItemID || items[index].compositionID.map(groupIDs.contains) == true) {
                items[index].compositionID = mergedCompositionID
            }
        }

        let genericURLTags: Set<String> = ["网页", "待读"]
        let mergedTags = Set(items[apiIndex].tags)
            .union(urlItem.tags.filter { !genericURLTags.contains($0) })
            .union(["URL已合并", "API密钥"])
        items[apiIndex].tags = mergedTags.sorted()
        items[apiIndex].isFavorite = items[apiIndex].isFavorite || urlItem.isFavorite
        items[apiIndex].userNote = Self.mergedNote(items[apiIndex].userNote, urlItem.userNote)
        items[apiIndex].organizationReason = "API 地址已从「\(urlItem.title)」吸收合并"
        items[apiIndex].collection = "账号"

        if let attachmentPath = urlItem.attachmentPath {
            PersistenceService.deleteAttachment(attachmentPath)
        }
        if let backupPath = urlItem.backupPath {
            LZFSEBackupService.deleteBackup(relativePath: backupPath)
        }
        if let secretKey = urlItem.secretKey {
            KeychainService.delete(key: secretKey)
        }
        if let webArchivePath = urlItem.webArchivePath {
            WebArchiveStorageService.delete(relativePath: webArchivePath)
        }
        items.removeAll { $0.id == urlItemID }
        if selectedItemID == urlItemID { selectedItemID = apiItemID }

        if let mergedCompositionID {
            let remainingCount = items.filter { !$0.isDeleted && $0.compositionID == mergedCompositionID }.count
            if remainingCount > 1 {
                normalizeCompositionOrder(mergedCompositionID)
                updateCompositionMetadata(mergedCompositionID)
            } else if let onlyIndex = items.firstIndex(where: { $0.compositionID == mergedCompositionID }) {
                items[onlyIndex].compositionID = nil
                items[onlyIndex].compositionKind = nil
                items[onlyIndex].compositionTitle = nil
                items[onlyIndex].compositionOrder = nil
            }
        }
    }

    private func collapseLegacyLLMCompositions() {
        let groupIDs = Set(items.compactMap { item in
            item.compositionKind == .llmAPI ? item.compositionID : nil
        })
        for groupID in groupIDs {
            guard let apiItem = items.first(where: { $0.compositionID == groupID && $0.credentialType == .apiKey }),
                  let urlItem = items.first(where: {
                      $0.compositionID == groupID && $0.id != apiItem.id && Self.URLString(for: $0) != nil
                  }),
                  let baseURL = Self.URLString(for: urlItem) else { continue }
            configureAPIKey(apiItem.id, baseURL: baseURL, persistChange: false)
            absorbURLRecord(urlItem.id, into: apiItem.id)
        }
    }

    private func consumeClipboardPayload(_ payload: String) {
        guard let candidateText = clipboardCandidate?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              candidateText == payload else { return }
        clipboardCandidate = nil
    }

    private func orderedCompositionIndices(_ compositionID: UUID) -> [Int] {
        items.indices
            .filter { items[$0].compositionID == compositionID && !items[$0].isDeleted }
            .sorted {
                let leftOrder = items[$0].compositionOrder ?? Int.max
                let rightOrder = items[$1].compositionOrder ?? Int.max
                if leftOrder == rightOrder { return items[$0].createdAt < items[$1].createdAt }
                return leftOrder < rightOrder
            }
    }

    private func applyCompositionOrder(_ orderedIndices: [Int]) {
        for (order, itemIndex) in orderedIndices.enumerated() {
            items[itemIndex].compositionOrder = order
        }
    }

    private func normalizeCompositionOrder(_ compositionID: UUID) {
        applyCompositionOrder(orderedCompositionIndices(compositionID))
    }

    private func updateCompositionMetadata(_ compositionID: UUID) {
        let memberIndices = items.indices.filter { items[$0].compositionID == compositionID && !items[$0].isDeleted }
        guard memberIndices.count > 1 else { return }
        let members = memberIndices.map { items[$0] }

        let hasAPIConfiguration = members.contains { $0.credentialType == .apiKey }
            && members.contains { Self.URLString(for: $0) != nil && $0.credentialType != .apiKey }
        let videoCount = members.filter(Self.isVideo).count
        let kind: CaptureCompositionKind = hasAPIConfiguration ? .llmAPI : (videoCount >= 2 ? .videoGroup : .related)
        let title: String
        switch kind {
        case .llmAPI:
            let provider = members.first(where: { $0.credentialType == .apiKey }).map(LLMProviderCatalog.displayName(for:)) ?? "LLM"
            title = "\(provider) API 配置"
        case .videoGroup:
            title = "视频组合 · \(memberIndices.count) 项"
        case .related:
            title = "资料组合 · \(memberIndices.count) 项"
        }

        for index in memberIndices {
            items[index].compositionKind = kind
            items[index].compositionTitle = title
        }
    }

    private static func URLString(for item: CaptureItem) -> String? {
        if item.kind == .web { return strictURLString(item.body) }
        if item.kind == .text, !item.body.contains("\n") { return strictURLString(item.body) }
        return nil
    }

    private static func strictURLString(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              clean.hasPrefix("http://") || clean.hasPrefix("https://") || clean.contains(".") else { return nil }
        guard let normalized = normalizedOptionalURL(clean),
              URL(string: normalized)?.host(percentEncoded: false) != nil else { return nil }
        return normalized
    }

    private static func mergedNote(_ first: String?, _ second: String?) -> String? {
        let values = [first, second]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else { return nil }
        return Array(NSOrderedSet(array: values)).compactMap { $0 as? String }.joined(separator: "\n\n")
    }

    private static func isVideo(_ item: CaptureItem) -> Bool {
        let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm", "mkv", "avi", "mpeg", "mpg"]
        if let fileExtension = item.fileExtension?.lowercased(), videoExtensions.contains(fileExtension) { return true }
        guard item.kind == .web,
              let url = URL(string: item.body),
              let host = url.host(percentEncoded: false)?.lowercased() else { return false }
        return host.contains("youtube.com") || host == "youtu.be" || host.contains("bilibili.com")
            || host.contains("vimeo.com") || host.contains("douyin.com") || host.contains("tiktok.com")
    }

    func attachmentURL(for item: CaptureItem) -> URL? {
        if let original = FileReferenceService.resolve(bookmark: item.fileBookmark, fallbackPath: item.originalLocation) {
            return original
        }
        if let path = item.attachmentPath, let attachment = PersistenceService.resolveAttachment(path) {
            return attachment
        }
        if let backupPath = item.backupPath, let fileName = item.fileName {
            return LZFSEBackupService.restoredURL(relativePath: backupPath, originalName: fileName)
        }
        return nil
    }

    private func insert(_ item: CaptureItem, silent: Bool = false) {
        items.insert(item, at: 0)
        if !silent {
            navigation = CaptureNavigation(destination: .category(.inbox), selectedItemID: item.id)
            lastConfirmation = item.textFormat.map { "已识别为\($0.title)，并保存为 .\($0.fileExtension) 文件" }
                ?? "已存入收件箱，正在自动整理"
        }
        persist()
        if persistenceEnabled, item.kind == .web {
            requestWebArchive(for: item.id)
        }
        if !silent {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2.2))
                self?.lastConfirmation = nil
            }
        }
    }

    private func isDuplicate(_ candidate: ClipboardCandidate) -> Bool {
        if let text = candidate.text {
            let detected = ContentDetector.detect(text: text)
            let storedBody = detected.textFormat == nil ? detected.body : text
            return duplicateItem(for: detected, storedBody: storedBody) != nil
        }
        if let fileURL = candidate.fileURL {
            return items.contains { $0.originalLocation == fileURL.path }
        }
        if let imageData = candidate.imageData {
            let fingerprint = CaptureContentIdentity.dataFingerprint(imageData)
            return items.contains { $0.contentFingerprint == fingerprint }
        }
        return false
    }

    private func duplicateItem(for detected: DetectedContent, storedBody: String) -> CaptureItem? {
        if detected.kind == .credential {
            return duplicateCredential(for: detected)
        }

        let fingerprint = CaptureContentIdentity.textFingerprint(storedBody)
        let normalized = CaptureContentIdentity.normalizedText(storedBody)
        return items.first { item in
            guard item.kind == .text || item.kind == .web else { return false }
            if item.contentFingerprint == fingerprint { return true }
            return CaptureContentIdentity.normalizedText(item.body) == normalized
        }
    }

    private func duplicateCredential(for detected: DetectedContent) -> CaptureItem? {
        items.first { item in
            guard item.kind == .credential,
                  item.credentialType == detected.credentialType else { return false }

            if let incomingSecret = detected.password,
               let secretKey = item.secretKey,
               KeychainService.load(key: secretKey) == incomingSecret {
                if detected.credentialType == .apiKey { return true }
                return CaptureContentIdentity.normalizedText(item.username ?? "")
                    == CaptureContentIdentity.normalizedText(detected.username ?? "")
            }

            guard detected.password == nil else { return false }
            return CaptureContentIdentity.normalizedText(item.body)
                    == CaptureContentIdentity.normalizedText(detected.body)
                && item.title == detected.title
        }
    }

    private func handleDuplicate(_ duplicate: CaptureItem, silent: Bool) {
        guard let index = items.firstIndex(where: { $0.id == duplicate.id }) else { return }
        let wasDeleted = items[index].isDeleted

        if wasDeleted && !silent {
            items[index].isDeleted = false
            items[index].createdAt = .now
            persist()
        }

        guard !silent else { return }
        navigation = CaptureNavigation(destination: .category(.inbox), selectedItemID: duplicate.id)
        showConfirmation(
            wasDeleted
                ? "相同内容已存在，已从回收站恢复"
                : "相同内容已存在，没有重复保存"
        )
    }

    private func navigate(to destination: CaptureDestination, selecting preferredItemID: CaptureItem.ID? = nil) {
        let matches = items.filter(destination.includes).sorted { $0.createdAt > $1.createdAt }
        let selection = preferredItemID.flatMap { preferred in
            matches.contains(where: { $0.id == preferred }) ? preferred : nil
        } ?? matches.first?.id
        let next = CaptureNavigation(destination: destination, selectedItemID: selection)
        guard navigation != next else { return }
        navigation = next
    }

    private func shouldAutoCapture(_ candidate: ClipboardCandidate) -> Bool {
        switch candidate.kind {
        case .credential:
            return false
        case .text:
            guard let text = candidate.text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
            return text.count >= 12 || text.contains("\n")
        case .image, .web, .file:
            return true
        }
    }

    private func mutate(_ id: CaptureItem.ID, change: (inout CaptureItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        persist()
    }

    private func persist() {
        guard persistenceEnabled else { return }
        PersistenceService.saveItems(items)
    }

    private func showConfirmation(_ message: String) {
        lastConfirmation = message
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.2))
            if self?.lastConfirmation == message { self?.lastConfirmation = nil }
        }
    }

    private func deleteResources(for item: CaptureItem) {
        if let key = item.secretKey { KeychainService.delete(key: key) }
        if let path = item.attachmentPath { PersistenceService.deleteAttachment(path) }
        if let backupPath = item.backupPath { LZFSEBackupService.deleteBackup(relativePath: backupPath) }
        if let webArchivePath = item.webArchivePath { WebArchiveStorageService.delete(relativePath: webArchivePath) }
    }

    private static func firstURL(in text: String) -> String? {
        text.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "，,；;。")) }
            .first { $0.hasPrefix("http://") || $0.hasPrefix("https://") }
    }

    private static func normalizedOptionalURL(_ value: String) -> String? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if clean.lowercased().hasPrefix("http://") || clean.lowercased().hasPrefix("https://") {
            return clean
        }
        return "https://" + clean
    }

    private static func organize(items: inout [CaptureItem]) {
        for index in items.indices {
            if items[index].collection == nil {
                items[index].collection = suggestedCollection(for: items[index].kind, tags: items[index].tags)
                items[index].organizationReason = organizationReason(for: items[index].kind)
            }
            if items[index].kind == .credential, items[index].platform?.isEmpty != false {
                items[index].platform = CredentialPlatformCatalog.infer(
                    title: items[index].title,
                    domain: items[index].domain,
                    loginURL: items[index].loginURL
                )
            }
            if items[index].kind == .credential, items[index].credentialType == nil {
                items[index].credentialType = items[index].tags.contains("API密钥") ? .apiKey : .account
            }
        }
    }

    private static func backfillContentFingerprints(items: inout [CaptureItem]) {
        for index in items.indices where items[index].contentFingerprint == nil {
            switch items[index].kind {
            case .text, .web:
                items[index].contentFingerprint = CaptureContentIdentity.textFingerprint(items[index].body)
            case .image, .credential, .file:
                break
            }
        }
    }

    private static func migratePreviouslyCapturedAPIKeys(items: inout [CaptureItem]) {
        for index in items.indices {
            guard items[index].kind != .credential,
                  let detected = LLMAPIKeyDetector.detect(in: items[index].body) else { continue }

            let keychainReference = items[index].secretKey ?? items[index].id.uuidString
            guard KeychainService.save(secret: detected.key, key: keychainReference) else { continue }

            if let attachmentPath = items[index].attachmentPath {
                PersistenceService.deleteAttachment(attachmentPath)
            }

            let provider = detected.provider ?? "OpenAI 兼容 / 待确认"
            let baseURL = detected.baseURL
            items[index].kind = .credential
            items[index].title = "\(provider) · API 密钥"
            items[index].body = "API 密钥已安全保存"
            items[index].summary = baseURL == nil
                ? "旧记录中的 API 密钥已安全迁移到 macOS 钥匙串，Base URL 待确认。"
                : "旧记录中的 API 密钥已安全迁移到 macOS 钥匙串，并已配置 API Base URL。"
            items[index].tags = Array(Set(items[index].tags + ["API密钥", provider, "受保护"])).sorted()
            items[index].textFormat = nil
            items[index].attachmentPath = nil
            items[index].fileName = nil
            items[index].fileSize = nil
            items[index].fileExtension = nil
            items[index].username = detected.keyLabel
            items[index].secretKey = keychainReference
            items[index].credentialType = .apiKey
            items[index].platform = provider
            items[index].domain = baseURL.flatMap { URL(string: $0)?.host(percentEncoded: false) }
            items[index].loginURL = nil
            items[index].apiBaseURL = baseURL
            items[index].collection = "账号"
            items[index].organizationReason = "旧记录中的 API 密钥已迁移到本机保险箱"
            items[index].securityLevel = .sensitive
            items[index].needsReview = baseURL == nil
        }
    }

    private static func markInvalidAccessWallArchives(items: inout [CaptureItem]) {
        for index in items.indices where items[index].kind == .web && items[index].webArchiveState == .archived {
            let title = items[index].title.lowercased()
            let isPrivateWall = title.contains("private")
                || title.contains("需要登录")
                || title.contains("无权访问")
                || (items[index].webRootDomain == "linux.do" && title.contains("找不到页面"))
            guard isPrivateWall else { continue }
            items[index].webArchiveState = .loginRequired
            items[index].webArchiveMessage = "当前本机文件是站点访问墙；请登录后覆盖为完整帖子存档"
        }
    }

    private static func backfillSourceApplications(items: inout [CaptureItem]) {
        let prefix = "无感记录 · "
        for index in items.indices where items[index].sourceApplication == nil {
            let source = items[index].source
            guard source.hasPrefix(prefix) else { continue }
            let app = String(source.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !app.isEmpty, app != "剪贴板", app != "监测文件夹" {
                items[index].sourceApplication = app
            }
        }
    }
    private static func suggestedCollection(for kind: CaptureKind, tags: [String]) -> String {
        switch kind {
        case .credential:
            "账号"
        case .file:
            "资料"
        case .web:
            "阅读"
        case .image:
            "灵感"
        case .text:
            if tags.contains("行动") { "行动" }
            else if tags.contains("阅读") { "阅读" }
            else if tags.contains("灵感") { "灵感" }
            else { "随想" }
        }
    }

    private static func organizationReason(for kind: CaptureKind) -> String {
        switch kind {
        case .credential: "识别为账号信息，自动归入账号"
        case .file: "识别为本地文件，自动归入资料"
        case .web: "识别为网页，自动归入阅读"
        case .image: "识别为图片，自动归入灵感"
        case .text: "根据文字主题自动整理"
        }
    }

}

struct CaptureFocusRequest: Equatable, Sendable {
    let token = UUID()
    let itemID: CaptureItem.ID
}
