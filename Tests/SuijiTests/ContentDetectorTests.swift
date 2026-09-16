import XCTest
import UniformTypeIdentifiers
import AppKit
@testable import Suiji

final class ContentDetectorTests: XCTestCase {
    func testDetectsWebURL() {
        let result = ContentDetector.detect(text: "https://example.com/article")
        XCTAssertEqual(result.kind, .web)
        XCTAssertEqual(result.title, "example.com")
    }

    func testDetectsCredentialAndSeparatesPassword() {
        let result = ContentDetector.detect(text: "微信工作号\n账号：qinghe.design\n密码：riverstone-2048")
        XCTAssertEqual(result.kind, .credential)
        XCTAssertEqual(result.username, "qinghe.design")
        XCTAssertEqual(result.password, "riverstone-2048")
        XCTAssertFalse(result.body.contains("riverstone-2048"))
        XCTAssertNil(result.textFormat)
    }

    func testPlainTextRemainsText() {
        let result = ContentDetector.detect(text: "真正的专注来自清晰的下一步")
        XCTAssertEqual(result.kind, .text)
        XCTAssertTrue(result.tags.contains("行动"))
    }

    func testOTPIsTreatedAsSensitiveCredential() {
        XCTAssertEqual(ContentDetector.inferredKind(for: "验证码：483921"), .credential)
        XCTAssertEqual(ContentDetector.inferredKind(for: "483921"), .credential)
    }

    func testImageFileKindUsesSystemTypeInformation() {
        XCTAssertEqual(ContentDetector.kind(for: URL(fileURLWithPath: "/tmp/reference.png")), .image)
        XCTAssertEqual(ContentDetector.kind(for: URL(fileURLWithPath: "/tmp/notes.pdf")), .file)
    }

    func testLinkedFileKeepsOriginalWithoutCreatingBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("原始资料.txt")
        try Data("只引用这份文件".utf8).write(to: source)
        let result = FileReferenceService.register(url: source, itemID: UUID(), mode: .linked)

        XCTAssertEqual(result.originalPath, source.path)
        XCTAssertNil(result.backupPath)
        let resolved = try XCTUnwrap(FileReferenceService.resolve(bookmark: result.bookmark, fallbackPath: result.originalPath))
        XCTAssertEqual(resolved.resolvingSymlinksInPath(), source.resolvingSymlinksInPath())
    }

    func testLZFSEBackupRoundTripsLosslesslyAndCompressesRepeatedData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let backups = root.appendingPathComponent("backups", isDirectory: true)
        let restores = root.appendingPathComponent("restores", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("long-notes.txt")
        let original = Data(String(repeating: "随记会无损保留这段资料。\n", count: 4_000).utf8)
        try original.write(to: source)

        let result = try XCTUnwrap(LZFSEBackupService.createBackup(
            from: source,
            itemID: UUID(),
            destinationDirectory: backups
        ))
        XCTAssertLessThan(result.compressedSize, result.originalSize)

        let restoredURL = try XCTUnwrap(LZFSEBackupService.restoredURL(
            relativePath: result.relativePath,
            originalName: source.lastPathComponent,
            sourceDirectory: backups,
            restoreDirectory: restores
        ))
        XCTAssertEqual(try Data(contentsOf: restoredURL), original)
    }

    func testSearchDateScopesUseExpectedBoundaries() {
        let now = Date()
        XCTAssertTrue(SearchDateScope.today.includes(now, now: now))
        XCTAssertTrue(SearchDateScope.week.includes(now.addingTimeInterval(-6 * 24 * 60 * 60), now: now))
        XCTAssertFalse(SearchDateScope.week.includes(now.addingTimeInterval(-8 * 24 * 60 * 60), now: now))
        XCTAssertTrue(SearchDateScope.month.includes(now.addingTimeInterval(-20 * 24 * 60 * 60), now: now))
    }

    func testCredentialInsightsNeverIncludeSecretValue() {
        let item = CaptureItem(
            kind: .credential,
            title: "示例账号",
            source: "测试",
            tags: ["账号"],
            summary: "账号由系统钥匙串保护。",
            username: "hello@example.com",
            secretKey: "keychain-key",
            collection: "账号"
        )
        let joined = CaptureInsightService.keyPoints(for: item).joined(separator: " ")
        XCTAssertTrue(joined.contains("hello@example.com"))
        XCTAssertFalse(joined.contains("keychain-key"))
    }

    func testCredentialPlatformIsInferredFromTitleAndLoginDomain() {
        XCTAssertEqual(
            CredentialPlatformCatalog.infer(title: "工作账号", domain: "github.com", loginURL: nil),
            "GitHub"
        )
        XCTAssertEqual(
            CredentialPlatformCatalog.infer(title: "微信工作号", domain: nil, loginURL: nil),
            "微信"
        )
        XCTAssertEqual(
            CredentialPlatformCatalog.infer(title: "公司后台账号", domain: nil, loginURL: nil),
            "公司后台"
        )
    }

    func testCredentialPlatformPersistsAndOlderRecordsRemainDecodable() throws {
        let item = CaptureItem(
            kind: .credential,
            title: "GitHub · 账号",
            source: "测试",
            username: "octocat",
            platform: "GitHub",
            loginURL: "https://github.com/login"
        )
        let encoded = try JSONEncoder().encode(item)
        XCTAssertEqual(try JSONDecoder().decode(CaptureItem.self, from: encoded).platform, "GitHub")

        let oldJSON = """
        {
          "id":"00000000-0000-0000-0000-000000000001",
          "createdAt":0,
          "kind":"credential",
          "title":"旧账号",
          "body":"账号：old-user",
          "source":"迁移测试",
          "tags":["账号"],
          "summary":"",
          "isFavorite":false,
          "isDeleted":false
        }
        """.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(CaptureItem.self, from: oldJSON).platform)
    }

    func testFileFormatDescriptorCoversCommonDocumentFamilies() {
        XCTAssertEqual(
            FileFormatDescriptor.describe(url: URL(fileURLWithPath: "/tmp/report.pdf"), fallbackExtension: nil).category,
            "便携文档"
        )
        XCTAssertEqual(
            FileFormatDescriptor.describe(url: URL(fileURLWithPath: "/tmp/table.xlsx"), fallbackExtension: nil).category,
            "电子表格"
        )
        XCTAssertEqual(
            FileFormatDescriptor.describe(url: URL(fileURLWithPath: "/tmp/slides.key"), fallbackExtension: nil).category,
            "演示文稿"
        )
    }

    func testRecognizesMarkdownAndUsesHeadingAsFileTitle() {
        let markdown = """
        # 随记格式识别方案

        这是一份会被自动保存的说明。

        - 识别标题
        - 保留列表
        - 支持 [相关链接](https://example.com)
        """

        XCTAssertEqual(TextFormatDetector.detect(markdown), .markdown)
        XCTAssertEqual(TextFormatDetector.suggestedTitle(for: markdown, format: .markdown), "随记格式识别方案")
        let result = ContentDetector.detect(text: markdown)
        XCTAssertEqual(result.textFormat, .markdown)
        XCTAssertEqual(result.title, "随记格式识别方案")
        XCTAssertTrue(result.tags.contains("Markdown"))
    }

    func testRecognizesStructuredTextAndCommonCodeFormats() {
        XCTAssertEqual(TextFormatDetector.detect(#"{"name":"随记","enabled":true}"#), .json)
        XCTAssertEqual(TextFormatDetector.detect("name: suiji\nenabled: true\nmode: local"), .yaml)
        XCTAssertEqual(TextFormatDetector.detect("name,kind,count\nA,text,3\nB,file,4"), .csv)
        XCTAssertEqual(TextFormatDetector.detect("import SwiftUI\nstruct ContentView: View {\n  var body: some View { Text(\"Hi\") }\n}"), .swift)
    }

    func testLongUnstructuredTextFallsBackToPlainTextWithoutMisclassifyingShortNotes() {
        XCTAssertNil(TextFormatDetector.detect("明天记得整理桌面"))
        let longText = String(repeating: "这是一段没有特殊语法但需要完整保存的长文本。", count: 20)
        XCTAssertEqual(TextFormatDetector.detect(longText), .plainText)
    }

    func testGeneratedTextFilePreservesOriginalContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let content = "# 标题\n\n- 第一项\n- 第二项\n"
        let itemID = UUID()
        let relativePath = try XCTUnwrap(PersistenceService.saveTextContent(
            content,
            itemID: itemID,
            fileName: "标题.md",
            destinationDirectory: root
        ))
        let savedURL = root.appendingPathComponent(relativePath)
        XCTAssertEqual(savedURL.pathExtension, "md")
        XCTAssertEqual(try String(contentsOf: savedURL, encoding: .utf8), content)
    }

    func testWebPreviewCacheKeyIgnoresFragmentsAndDefaultPorts() throws {
        let first = try XCTUnwrap(URL(string: "HTTPS://Example.COM:443/article?id=7#comments"))
        let second = try XCTUnwrap(URL(string: "https://example.com/article?id=7#top"))

        XCTAssertEqual(
            WebPreviewCachePolicy.canonicalURLString(for: first),
            WebPreviewCachePolicy.canonicalURLString(for: second)
        )
        XCTAssertEqual(
            WebPreviewCachePolicy.cacheKey(for: first),
            WebPreviewCachePolicy.cacheKey(for: second)
        )
    }

    func testWebPreviewCacheKeepsDifferentPagesSeparate() throws {
        let first = try XCTUnwrap(URL(string: "https://example.com/article-a"))
        let second = try XCTUnwrap(URL(string: "https://example.com/article-b"))

        XCTAssertNotEqual(
            WebPreviewCachePolicy.cacheKey(for: first),
            WebPreviewCachePolicy.cacheKey(for: second)
        )
        XCTAssertEqual(WebPreviewCachePolicy.maximumConcurrentLoads, 3)
    }

    func testWebsiteIdentitySharesOneSessionAcrossSubdomains() throws {
        let topic = try XCTUnwrap(URL(string: "https://linux.do/t/topic/123"))
        let assets = try XCTUnwrap(URL(string: "https://cdn.linux.do/images/a.png"))
        let chineseSite = try XCTUnwrap(URL(string: "https://bbs.example.com.cn/thread/1"))

        XCTAssertEqual(WebsiteIdentity.rootDomain(for: topic), "linux.do")
        XCTAssertEqual(WebsiteIdentity.rootDomain(for: assets), "linux.do")
        XCTAssertEqual(WebsiteIdentity.rootDomain(for: chineseSite), "example.com.cn")
        XCTAssertEqual(WebsiteIdentity.rootURL(for: topic).absoluteString, "https://linux.do")
    }

    func testPrivate404RequiresLoginInsteadOfArchivingAccessWall() {
        XCTAssertEqual(
            WebArchiveAccessPolicy.decision(
                statusCode: 404,
                looksLikeLogin: false,
                looksLikePrivateMissingPage: true
            ),
            .loginRequired
        )
        XCTAssertEqual(
            WebArchiveAccessPolicy.decision(
                statusCode: 404,
                looksLikeLogin: false,
                looksLikePrivateMissingPage: false
            ),
            .failedStatus(404)
        )
        XCTAssertEqual(
            WebArchiveAccessPolicy.decision(
                statusCode: 200,
                looksLikeLogin: false,
                looksLikePrivateMissingPage: false
            ),
            .archive
        )
    }

    func testWebArchiveStorageRoundTripsLZFSEData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stored = root.appendingPathComponent("stored", isDirectory: true)
        let restored = root.appendingPathComponent("restored", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let archiveData = Data(String(repeating: "<article>需要登录的完整帖子内容</article>", count: 2_000).utf8)
        let result = try XCTUnwrap(WebArchiveStorageService.store(
            archiveData,
            itemID: UUID(),
            destinationDirectory: stored
        ))
        XCTAssertLessThan(result.compressedSize, result.originalSize)

        let restoredURL = try XCTUnwrap(WebArchiveStorageService.restoredURL(
            relativePath: result.relativePath,
            sourceDirectory: stored,
            destinationDirectory: restored
        ))
        XCTAssertEqual(try Data(contentsOf: restoredURL), archiveData)
        XCTAssertEqual(restoredURL.pathExtension, "webarchive")
    }

    func testWebArchiveMetadataRemainsBackwardCompatible() throws {
        let item = CaptureItem(
            kind: .web,
            title: "Linux DO 帖子",
            body: "https://linux.do/t/topic/123",
            source: "测试",
            domain: "linux.do",
            webRootDomain: "linux.do",
            webArchiveState: .archived,
            webArchivePath: "id.webarchive.lzfse",
            webArchiveCapturedAt: Date(timeIntervalSince1970: 100),
            webArchiveOriginalSize: 10_000,
            webArchiveCompressedSize: 4_000,
            webArchiveMessage: "已保存"
        )
        let decoded = try JSONDecoder().decode(CaptureItem.self, from: JSONEncoder().encode(item))
        XCTAssertEqual(decoded.webArchiveState, .archived)
        XCTAssertEqual(decoded.webRootDomain, "linux.do")
        XCTAssertEqual(decoded.webArchiveCompressedSize, 4_000)
    }

    func testFormattedTextRecordRemainsBackwardCompatible() throws {
        let item = CaptureItem(
            kind: .text,
            title: "Markdown 记录",
            body: "# Markdown 记录",
            source: "测试",
            textFormat: .markdown,
            attachmentPath: "Text/id/Markdown 记录.md",
            fileName: "Markdown 记录.md",
            fileSize: 17,
            fileExtension: "MD"
        )
        let data = try JSONEncoder().encode(item)
        let decoded = try JSONDecoder().decode(CaptureItem.self, from: data)
        XCTAssertEqual(decoded.textFormat, .markdown)
        XCTAssertEqual(decoded.fileName, "Markdown 记录.md")
    }

    func testBundledExampleMigrationRemovesOnlyExactExamples() {
        let example = CaptureItem(
            kind: .web,
            title: "A List Apart — Design systems are for people",
            body: "https://alistapart.com",
            source: "Safari 分享"
        )
        let realCaptureWithSimilarTitle = CaptureItem(
            kind: .web,
            title: "A List Apart — Design systems are for people",
            body: "https://alistapart.com/new-article",
            source: "剪贴板"
        )

        let result = BundledSampleMigration.removeExamples(
            from: [example, realCaptureWithSimilarTitle]
        )

        XCTAssertEqual(result.removed, [example])
        XCTAssertEqual(result.kept, [realCaptureWithSimilarTitle])
    }

    func testTimelineSectionsKeepDaysSeparateAndNewestFirst() {
        let calendar = Calendar(identifier: .gregorian)
        let newer = CaptureItem(
            createdAt: calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 20))!,
            kind: .text,
            title: "较新",
            source: "测试"
        )
        let older = CaptureItem(
            createdAt: calendar.date(from: DateComponents(year: 2026, month: 8, day: 2, hour: 8))!,
            kind: .text,
            title: "较早",
            source: "测试"
        )

        let sections = CaptureTimelineSection.sections(from: [older, newer])

        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].items, [newer])
        XCTAssertEqual(sections[1].items, [older])
    }

    func testTimelineEntriesCollapseCompositionIntoOneVisibleGroup() {
        let groupID = UUID()
        let first = CaptureItem(
            createdAt: Date(timeIntervalSince1970: 100),
            kind: .text,
            title: "说明",
            source: "测试",
            compositionID: groupID,
            compositionKind: .related,
            compositionTitle: "资料组合 · 2 项"
        )
        let second = CaptureItem(
            createdAt: Date(timeIntervalSince1970: 200),
            kind: .image,
            title: "配图",
            source: "测试",
            compositionID: groupID,
            compositionKind: .related,
            compositionTitle: "资料组合 · 2 项"
        )
        let standalone = CaptureItem(
            createdAt: Date(timeIntervalSince1970: 300),
            kind: .web,
            title: "网页",
            source: "测试"
        )

        let entries = CaptureTimelineEntry.entries(from: [first, second, standalone])

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first?.item?.id, standalone.id)
        XCTAssertEqual(entries.last?.group?.members.map(\.id), [first.id, second.id])
        XCTAssertEqual(entries.last?.recordCount, 2)
    }

    func testCompositionGroupsAreSortedAndDescribeAllMemberTypes() {
        let olderGroup = UUID()
        let newerGroup = UUID()
        let items = [
            CaptureItem(createdAt: Date(timeIntervalSince1970: 10), kind: .text, title: "文字", source: "测试", compositionID: olderGroup, compositionKind: .related, compositionTitle: "旧组合"),
            CaptureItem(createdAt: Date(timeIntervalSince1970: 20), kind: .file, title: "文件", source: "测试", compositionID: olderGroup, compositionKind: .related, compositionTitle: "旧组合"),
            CaptureItem(createdAt: Date(timeIntervalSince1970: 30), kind: .web, title: "网页", source: "测试", compositionID: newerGroup, compositionKind: .related, compositionTitle: "新组合"),
            CaptureItem(createdAt: Date(timeIntervalSince1970: 40), kind: .image, title: "图片", source: "测试", compositionID: newerGroup, compositionKind: .related, compositionTitle: "新组合")
        ]

        let groups = CaptureCompositionGroup.groups(from: items)

        XCTAssertEqual(groups.map(\.id), [newerGroup, olderGroup])
        XCTAssertEqual(groups.first?.typeSummary, "网页 + 图片与截图")
    }

    func testCollectionDestinationDerivesOneStableNavigationTarget() {
        let destination = CaptureDestination.collection("灵感")
        let matching = CaptureItem(kind: .image, title: "真实截图", source: "测试", collection: "灵感")
        let other = CaptureItem(kind: .image, title: "其他图片", source: "测试", collection: "资料")

        XCTAssertEqual(destination.category, .all)
        XCTAssertEqual(destination.collection, "灵感")
        XCTAssertTrue(destination.includes(matching))
        XCTAssertFalse(destination.includes(other))
    }

    func testRecognizesLabeledOpenAIKeyAndConfiguredBaseURL() {
        let fakeKey = "sk-proj-test_abcdefghijklmnopqrstuvwxyz123456"
        let input = """
        OPENAI_API_KEY=\(fakeKey)
        OPENAI_BASE_URL=https://gateway.example.com/v1
        """

        let result = ContentDetector.detect(text: input)

        XCTAssertEqual(result.kind, .credential)
        XCTAssertEqual(result.credentialType, .apiKey)
        XCTAssertEqual(result.platform, "OpenAI")
        XCTAssertEqual(result.password, fakeKey)
        XCTAssertEqual(result.apiBaseURL, "https://gateway.example.com/v1")
        XCTAssertNil(result.textFormat)
        XCTAssertFalse(result.body.contains(fakeKey))
        XCTAssertFalse(result.summary.contains(fakeKey))
    }

    func testRecognizesProviderSpecificAPIKeyPrefixes() {
        let cases: [(String, String)] = [
            ("sk-ant-api03-test_abcdefghijklmnopqrstuvwxyz123456", "Anthropic Claude"),
            ("sk-or-v1-test_abcdefghijklmnopqrstuvwxyz123456", "OpenRouter"),
            ("gsk_test_abcdefghijklmnopqrstuvwxyz123456", "Groq"),
            ("xai-test_abcdefghijklmnopqrstuvwxyz123456", "xAI"),
            ("AIzaTest_abcdefghijklmnopqrstuvwxyz123456", "Google Gemini")
        ]

        for (fakeKey, provider) in cases {
            let detected = LLMAPIKeyDetector.detect(in: fakeKey)
            XCTAssertEqual(detected?.provider, provider)
            XCTAssertEqual(detected?.key, fakeKey)
            XCTAssertEqual(ContentDetector.inferredKind(for: fakeKey), .credential)
        }
    }

    func testGenericSKKeyIsSensitiveButProviderRemainsUncertain() {
        let fakeKey = "sk-test_abcdefghijklmnopqrstuvwxyz1234567890"
        let detected = LLMAPIKeyDetector.detect(in: fakeKey)

        XCTAssertNotNil(detected)
        XCTAssertNil(detected?.provider)
        XCTAssertNil(detected?.baseURL)
        let content = ContentDetector.detect(text: fakeKey)
        XCTAssertEqual(content.credentialType, .apiKey)
        XCTAssertEqual(content.platform, "OpenAI 兼容 / 待确认")
        XCTAssertEqual(content.password, fakeKey)
    }

    func testPlainMarkdownContainingAPIWordsDoesNotBecomeASecret() {
        let markdown = """
        # API 使用说明

        请把密钥放进环境变量，不要提交到仓库。
        Base URL 可以在设置中修改。

        - 不要粘贴真实密钥到说明文档
        - 参考 [安全规范](https://example.com/security)
        """

        let result = ContentDetector.detect(text: markdown)
        XCTAssertEqual(result.kind, .text)
        XCTAssertEqual(result.textFormat, .markdown)
        XCTAssertNil(result.password)
    }

    func testAPIKeyRecordPersistsConfigurationWithoutPersistingSecret() throws {
        let item = CaptureItem(
            kind: .credential,
            title: "OpenAI · API 密钥",
            body: "API 密钥已安全保存",
            source: "测试",
            username: "生产环境",
            secretKey: "keychain-reference-only",
            credentialType: .apiKey,
            platform: "OpenAI",
            domain: "api.openai.com",
            apiBaseURL: "https://api.openai.com/v1"
        )
        let data = try JSONEncoder().encode(item)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        let decoded = try JSONDecoder().decode(CaptureItem.self, from: data)

        XCTAssertEqual(decoded.credentialType, .apiKey)
        XCTAssertEqual(decoded.apiBaseURL, "https://api.openai.com/v1")
        XCTAssertFalse(json.contains("sk-test"))
        XCTAssertFalse(CaptureInsightService.keyPoints(for: item).joined().contains("keychain-reference-only"))
    }

    @MainActor
    func testDraggingAPIKeyAndURLAbsorbsURLIntoLLMConfiguration() {
        let api = CaptureItem(
            kind: .credential,
            title: "待确认 · API 密钥",
            source: "测试",
            tags: ["API密钥"],
            username: "默认密钥",
            credentialType: .apiKey,
            platform: "OpenAI 兼容 / 待确认"
        )
        let endpoint = CaptureItem(
            kind: .web,
            title: "OpenAI API",
            body: "https://api.openai.com/v1",
            source: "测试",
            tags: ["网关"],
            userNote: "团队统一入口",
            isFavorite: true
        )
        let store = CaptureStore(testItems: [api, endpoint])

        XCTAssertTrue(store.combine(endpoint.id, onto: api.id))

        let updatedAPI = store.items.first { $0.id == api.id }
        XCTAssertEqual(updatedAPI?.apiBaseURL, "https://api.openai.com/v1")
        XCTAssertEqual(updatedAPI?.platform, "OpenAI")
        XCTAssertEqual(store.items.count, 1)
        XCTAssertNil(store.items.first { $0.id == endpoint.id })
        XCTAssertNil(updatedAPI?.compositionID)
        XCTAssertTrue(updatedAPI?.tags.contains("网关") == true)
        XCTAssertEqual(updatedAPI?.userNote, "团队统一入口")
        XCTAssertTrue(updatedAPI?.isFavorite == true)
    }

    @MainActor
    func testDraggingVideosTogetherCreatesVideoGroup() {
        let first = CaptureItem(kind: .file, title: "片段 A.mov", source: "测试", fileExtension: "MOV")
        let second = CaptureItem(kind: .file, title: "片段 B.mp4", source: "测试", fileExtension: "MP4")
        let store = CaptureStore(testItems: [first, second])

        XCTAssertTrue(store.combine(first.id, onto: second.id))
        XCTAssertEqual(store.items.first { $0.id == first.id }?.compositionKind, .videoGroup)
        XCTAssertEqual(store.items.first { $0.id == second.id }?.compositionTitle, "视频组合 · 2 项")
    }

    @MainActor
    func testDraggingOrdinaryWebURLsKeepsBothRecordsAndWebRenderingData() {
        let first = CaptureItem(kind: .web, title: "文章 A", body: "https://example.com/a", source: "测试")
        let second = CaptureItem(kind: .web, title: "文章 B", body: "https://example.com/b", source: "测试")
        let store = CaptureStore(testItems: [first, second])

        XCTAssertTrue(store.combine(first.id, onto: second.id))
        XCTAssertEqual(store.items.count, 2)
        XCTAssertTrue(store.items.allSatisfy { $0.kind == .web && $0.body.hasPrefix("https://") })
        XCTAssertTrue(store.items.allSatisfy { $0.compositionKind == .related })
    }

    @MainActor
    func testLegacyLLMCompositionCollapsesToOneAPIRecordOnLoad() {
        let groupID = UUID()
        let api = CaptureItem(
            kind: .credential,
            title: "OpenAI · API 密钥",
            source: "测试",
            credentialType: .apiKey,
            platform: "OpenAI",
            compositionID: groupID,
            compositionKind: .llmAPI,
            compositionTitle: "OpenAI API 配置"
        )
        let endpoint = CaptureItem(
            kind: .web,
            title: "OpenAI API",
            body: "https://api.openai.com/v1",
            source: "测试",
            compositionID: groupID,
            compositionKind: .llmAPI,
            compositionTitle: "OpenAI API 配置"
        )

        let store = CaptureStore(testItems: [api, endpoint])

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.id, api.id)
        XCTAssertEqual(store.items.first?.apiBaseURL, "https://api.openai.com/v1")
        XCTAssertNil(store.items.first?.compositionID)
    }

    @MainActor
    func testRemovingOneOfTwoMembersDissolvesComposition() {
        let note = CaptureItem(kind: .text, title: "说明", source: "测试")
        let image = CaptureItem(kind: .image, title: "配图", source: "测试")
        let store = CaptureStore(testItems: [note, image])

        XCTAssertTrue(store.combine(note.id, onto: image.id))
        XCTAssertEqual(store.items.first { $0.id == note.id }?.compositionKind, .related)

        store.removeFromComposition(note.id)
        XCTAssertNil(store.items.first { $0.id == note.id }?.compositionID)
        XCTAssertNil(store.items.first { $0.id == image.id }?.compositionID)
    }

    @MainActor
    func testDissolvingWholeCompositionKeepsEveryOriginalRecord() {
        let first = CaptureItem(kind: .text, title: "说明", source: "测试")
        let second = CaptureItem(kind: .image, title: "图片", source: "测试")
        let third = CaptureItem(kind: .web, title: "网页", body: "https://example.com", source: "测试")
        let store = CaptureStore(testItems: [first, second, third])

        XCTAssertTrue(store.combine(first.id, onto: second.id))
        XCTAssertTrue(store.combine(third.id, onto: second.id))
        let groupID = store.items.first { $0.id == first.id }?.compositionID
        XCTAssertNotNil(groupID)

        store.dissolveComposition(groupID!)

        XCTAssertEqual(store.items.count, 3)
        XCTAssertTrue(store.items.allSatisfy { $0.compositionID == nil })
        XCTAssertTrue(store.items.allSatisfy { $0.compositionKind == nil })
    }

    @MainActor
    func testDroppingRawURLDirectlyFillsAPIRecordWithoutCreatingExtraItem() {
        let api = CaptureItem(
            kind: .credential,
            title: "Groq · API 密钥",
            source: "测试",
            credentialType: .apiKey,
            platform: "Groq"
        )
        let store = CaptureStore(testItems: [api])
        store.clipboardCandidate = ClipboardCandidate(
            kind: .web,
            displayText: "api.groq.com",
            text: "https://api.groq.com/openai/v1",
            imageData: nil,
            fileURL: nil
        )

        XCTAssertTrue(store.handleDroppedText("https://api.groq.com/openai/v1", onto: api.id))
        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.apiBaseURL, "https://api.groq.com/openai/v1")
        XCTAssertNil(store.items.first?.compositionID)
        XCTAssertNil(store.clipboardCandidate)
    }

    func testExactContentIdentityNormalizesOnlyOuterWhitespaceAndLineEndings() {
        XCTAssertEqual(
            CaptureContentIdentity.textFingerprint("第一行\r\n第二行\n"),
            CaptureContentIdentity.textFingerprint("  第一行\n第二行  ")
        )
        XCTAssertNotEqual(
            CaptureContentIdentity.textFingerprint("第一行\n第二行"),
            CaptureContentIdentity.textFingerprint("第一行\n第二行。")
        )
        XCTAssertNotEqual(
            CaptureContentIdentity.textFingerprint("Same Content"),
            CaptureContentIdentity.textFingerprint("same content")
        )
    }

    @MainActor
    func testCapturingIdenticalTextDoesNotCreateDuplicateRecord() {
        let existing = CaptureItem(
            kind: .text,
            title: "原记录",
            body: "完全相同的剪贴板内容",
            source: "测试"
        )
        let store = CaptureStore(testItems: [existing])

        store.capture(text: "  完全相同的剪贴板内容\n", source: "再次复制")

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items.first?.id, existing.id)
        XCTAssertEqual(store.lastConfirmation, "相同内容已存在，没有重复保存")
    }

    @MainActor
    func testCapturingDeletedDuplicateRestoresInsteadOfAddingAnotherRecord() {
        let existing = CaptureItem(
            kind: .text,
            title: "回收站记录",
            body: "需要重新找回的相同内容",
            source: "测试",
            isDeleted: true
        )
        let store = CaptureStore(testItems: [existing])

        store.capture(text: "需要重新找回的相同内容", source: "再次复制")

        XCTAssertEqual(store.items.count, 1)
        XCTAssertFalse(store.items[0].isDeleted)
        XCTAssertEqual(store.lastConfirmation, "相同内容已存在，已从回收站恢复")
    }

    @MainActor
    func testTrashRecordsCanBeRestoredAndDeletedInBatches() {
        let first = CaptureItem(kind: .text, title: "第一条", body: "A", source: "测试", isDeleted: true)
        let second = CaptureItem(kind: .text, title: "第二条", body: "B", source: "测试", isDeleted: true)
        let third = CaptureItem(kind: .text, title: "保留条目", body: "C", source: "测试")
        let store = CaptureStore(testItems: [first, second, third])

        store.restore(Set([first.id, second.id]))
        XCTAssertFalse(store.items.first { $0.id == first.id }!.isDeleted)
        XCTAssertFalse(store.items.first { $0.id == second.id }!.isDeleted)

        store.deletePermanently(Set([first.id, second.id]))
        XCTAssertEqual(store.items.map(\.id), [third.id])
        XCTAssertEqual(store.lastConfirmation, "已批量永久删除 2 条记录")
    }

    func testDeepSeekSearchPlanDecodesStructuredJSON() throws {
        let plan = try DeepSeekAISearchService.decodePlan(from: """
        ```json
        {"keywords":["GPT","大模型","GPT"],"kind":"web","dateScope":"week","startDate":null,"endDate":null,"collection":"阅读","explanation":"查找近一周的大模型网页"}
        ```
        """)

        XCTAssertEqual(Set(plan.keywords), Set(["GPT", "大模型"]))
        XCTAssertEqual(plan.kindScope, .web)
        XCTAssertEqual(plan.fallbackDateScope, .week)
        XCTAssertEqual(plan.collection, "阅读")
    }

    @MainActor
    func testAIPlanSearchesExpandedTermsLocallyWithoutSendingRecords() {
        let matching = CaptureItem(
            createdAt: .now,
            kind: .web,
            title: "GPT 模型更新",
            body: "https://example.com/gpt",
            source: "浏览器",
            tags: ["大模型"],
            collection: "阅读"
        )
        let wrongKind = CaptureItem(createdAt: .now, kind: .text, title: "GPT 随想", source: "测试", collection: "阅读")
        let wrongCollection = CaptureItem(createdAt: .now, kind: .web, title: "GPT 新闻", source: "测试", collection: "资料")
        let store = CaptureStore(testItems: [matching, wrongKind, wrongCollection])
        let plan = AISearchPlan(
            keywords: ["GPT", "大模型"], kind: "web", dateScope: "week",
            startDate: nil, endDate: nil, collection: "阅读", explanation: "本机匹配"
        )

        XCTAssertEqual(store.search("最近的大模型网页", using: plan).map(\.id), [matching.id])
    }

    @MainActor
    func testCompositionMembersCanBeReorderedPersistently() {
        let first = CaptureItem(createdAt: Date(timeIntervalSince1970: 10), kind: .text, title: "第一项", source: "测试")
        let second = CaptureItem(createdAt: Date(timeIntervalSince1970: 20), kind: .image, title: "第二项", source: "测试")
        let third = CaptureItem(createdAt: Date(timeIntervalSince1970: 30), kind: .file, title: "第三项", source: "测试")
        let store = CaptureStore(testItems: [first, second, third])

        XCTAssertTrue(store.combine(first.id, onto: second.id))
        XCTAssertTrue(store.combine(third.id, onto: second.id))
        let groupID = store.items.first { $0.id == first.id }!.compositionID!
        store.moveCompositionMember(third.id, in: groupID, before: first.id)

        let updatedFirst = store.items.first { $0.id == first.id }!
        XCTAssertEqual(store.compositionMembers(for: updatedFirst).map(\.id), [third.id, first.id, second.id])
        XCTAssertEqual(store.items.first { $0.id == third.id }?.compositionOrder, 0)
        XCTAssertEqual(store.items.first { $0.id == second.id }?.compositionOrder, 2)
    }

    @MainActor
    func testCompositionPreviewOrderCanBeCommittedAsOneAnimatedDrop() {
        let first = CaptureItem(createdAt: Date(timeIntervalSince1970: 10), kind: .text, title: "第一项", source: "测试")
        let second = CaptureItem(createdAt: Date(timeIntervalSince1970: 20), kind: .image, title: "第二项", source: "测试")
        let third = CaptureItem(createdAt: Date(timeIntervalSince1970: 30), kind: .file, title: "第三项", source: "测试")
        let store = CaptureStore(testItems: [first, second, third])

        XCTAssertTrue(store.combine(first.id, onto: second.id))
        XCTAssertTrue(store.combine(third.id, onto: second.id))
        let groupID = store.items.first { $0.id == first.id }!.compositionID!
        store.setCompositionMemberOrder([second.id, third.id, first.id], in: groupID)

        let updated = store.items.first { $0.id == second.id }!
        XCTAssertEqual(store.compositionMembers(for: updated).map(\.id), [second.id, third.id, first.id])
    }

    @MainActor
    func testRelatedContentRequiresARealSemanticOrExplicitRelationship() {
        let target = CaptureItem(
            kind: .text,
            title: "PPO 裁剪与策略稳定性",
            body: "PPO clipping 通过限制策略更新幅度改善强化学习训练稳定性。",
            source: "ChatGPT",
            sourceApplication: "ChatGPT",
            tags: ["强化学习", "PPO"],
            textFormat: .markdown
        )
        let unrelatedSameType = CaptureItem(
            kind: .text,
            title: "周末番茄炖牛肉食谱",
            body: "准备番茄、牛肉和香料，慢炖两个小时。",
            source: "ChatGPT",
            sourceApplication: "ChatGPT",
            tags: ["文字", "Markdown"],
            textFormat: .markdown
        )
        let relatedWeb = CaptureItem(
            kind: .web,
            title: "PPO clipping 训练说明",
            body: "https://example.com/ppo-clipping",
            source: "浏览器",
            tags: ["强化学习", "策略优化"]
        )
        let store = CaptureStore(testItems: [target, unrelatedSameType, relatedWeb])

        let matches = store.relatedMatches(to: target)

        XCTAssertEqual(matches.map(\.item.id), [relatedWeb.id])
        XCTAssertTrue(matches[0].reasons.contains { $0.contains("共同标签") || $0.contains("共同主题") })
    }

    @MainActor
    func testExplicitCompositionAlwaysProducesRelatedContent() {
        let groupID = UUID()
        let target = CaptureItem(
            kind: .text, title: "项目说明", source: "测试",
            compositionID: groupID, compositionKind: .related, compositionTitle: "资料组合", compositionOrder: 0
        )
        let member = CaptureItem(
            kind: .image, title: "架构草图", source: "测试",
            compositionID: groupID, compositionKind: .related, compositionTitle: "资料组合", compositionOrder: 1
        )
        let store = CaptureStore(testItems: [target, member])

        let matches = store.relatedMatches(to: target)

        XCTAssertEqual(matches.first?.item.id, member.id)
        XCTAssertEqual(matches.first?.reasons.first, "同一组合")
    }

    @MainActor
    func testFileDragProviderExportsInternalRecordAndRealFileURL() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("pdf")
        try Data("test-pdf".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let item = CaptureItem(
            kind: .file, title: "测试文件.pdf", source: "测试",
            fileName: "测试文件.pdf", originalLocation: url.path, fileExtension: "PDF"
        )
        let store = CaptureStore(testItems: [item])

        let provider = CaptureDragProvider.make(store: store, item: item)

        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.shixuCaptureRecord.identifier))
        XCTAssertTrue(provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier))
    }

    func testTimeAggregationSplitsSessionsByGapAndMonths() {
        let calendar = Calendar(identifier: .gregorian)
        let day = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 9))!
        let first = CaptureItem(createdAt: day, kind: .text, title: "上午一", source: "测试", sourceApplication: "Xcode")
        let second = CaptureItem(createdAt: day.addingTimeInterval(20 * 60), kind: .file, title: "上午二", source: "测试", sourceApplication: "Xcode")
        let third = CaptureItem(createdAt: day.addingTimeInterval(2 * 60 * 60), kind: .web, title: "午间网页", source: "测试")

        let clusters = CaptureTimeCluster.clusters(from: [first, second, third])

        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters.last?.items.map(\.id), [second.id, first.id])
        XCTAssertEqual(CaptureTimeClusterMonth.months(from: [first, second, third]).first?.recordCount, 3)
    }

    func testTimeAggregationBuildsNewestFirstDaySections() {
        let calendar = Calendar(identifier: .gregorian)
        let olderDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 4, hour: 21))!
        let newerDay = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 9))!
        let older = CaptureItem(createdAt: olderDay, kind: .text, title: "前一天", source: "测试")
        let newerA = CaptureItem(createdAt: newerDay, kind: .image, title: "当天截图", source: "测试")
        let newerB = CaptureItem(createdAt: newerDay.addingTimeInterval(2 * 60 * 60), kind: .web, title: "当天网页", source: "测试")

        let days = CaptureTimeClusterDay.days(from: [older, newerA, newerB])

        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days.first?.recordCount, 2)
        XCTAssertEqual(days.first?.clusters.count, 2)
        XCTAssertEqual(days.last?.clusters.first?.items.first?.id, older.id)
    }

    func testCalendarPagesShiftAtTheirSelectedLevel() {
        let calendar = CaptureCalendarPage.calendar
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6, hour: 12))!

        let month = CaptureCalendarPage(level: .month, anchor: anchor)
        let nextMonth = CaptureCalendarPage(level: .month, anchor: month.shifted(by: 1))
        let nextWeek = CaptureCalendarPage(level: .week, anchor: CaptureCalendarPage(level: .week, anchor: anchor).shifted(by: 1))

        XCTAssertEqual(calendar.component(.month, from: nextMonth.anchor), 9)
        XCTAssertEqual(calendar.dateComponents([.day], from: anchor, to: nextWeek.anchor).day, 7)
        XCTAssertTrue(month.contains(anchor))
        XCTAssertFalse(month.contains(nextMonth.anchor))
    }

    func testMonthCalendarGridUsesCompleteMondayFirstWeeks() {
        let calendar = CaptureCalendarPage.calendar
        let anchor = calendar.date(from: DateComponents(year: 2026, month: 8, day: 6))!
        let page = CaptureCalendarPage(level: .month, anchor: anchor)

        XCTAssertEqual(page.monthGridDays.count % 7, 0)
        XCTAssertEqual(calendar.component(.weekday, from: page.monthGridDays.first!), 2)
        XCTAssertEqual(calendar.component(.weekday, from: page.monthGridDays.last!), 1)
    }

    @MainActor
    func testSystemRightClickServiceAcceptsMultipleFinderItems() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        pasteboard.clearContents()
        let fileURL = URL(fileURLWithPath: "/tmp/拾序测试.pdf")
        let folderURL = URL(fileURLWithPath: "/tmp/拾序资料", isDirectory: true)
        XCTAssertTrue(pasteboard.writeObjects([fileURL as NSURL, folderURL as NSURL]))

        let urls = SystemServicesProvider.fileURLs(from: pasteboard)

        XCTAssertEqual(urls, [fileURL.standardizedFileURL, folderURL.standardizedFileURL])
    }

    @MainActor
    func testCaptureRuntimePersistsPauseAndResumeChoice() {
        let suiteName = "CaptureRuntimeControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let runtime = CaptureRuntimeController(defaults: defaults)

        XCTAssertTrue(runtime.isCaptureEnabled)
        runtime.setCaptureEnabled(false)
        XCTAssertFalse(runtime.isCaptureEnabled)
        XCTAssertFalse(defaults.bool(forKey: "ambientCaptureEnabled"))

        runtime.setCaptureEnabled(true)
        XCTAssertTrue(runtime.isCaptureEnabled)
        XCTAssertTrue(defaults.bool(forKey: "ambientCaptureEnabled"))
    }

    @MainActor
    func testCaptureRuntimeActuallyStopsAndRestartsClipboardPolling() {
        let suiteName = "CaptureRuntimeServiceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let runtime = CaptureRuntimeController(defaults: defaults)
        let store = CaptureStore(testItems: [])

        runtime.start(store: store)
        XCTAssertTrue(ClipboardMonitor.shared.isRunning)

        runtime.setCaptureEnabled(false)
        XCTAssertFalse(ClipboardMonitor.shared.isRunning)

        runtime.setCaptureEnabled(true)
        XCTAssertTrue(ClipboardMonitor.shared.isRunning)
        runtime.shutdown()
        XCTAssertFalse(ClipboardMonitor.shared.isRunning)
    }

    @MainActor
    func testDockMenuReflectsRuntimeStateAndContainsQuickActions() {
        let suiteName = "DockMenuControllerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let runtime = CaptureRuntimeController(defaults: defaults)
        let store = CaptureStore(testItems: [])

        runtime.setCaptureEnabled(false)
        let pausedMenu = DockMenuController.shared.makeMenu(store: store, runtime: runtime)
        let pausedTitles = pausedMenu.items.map(\.title)
        XCTAssertTrue(pausedTitles.contains("开始后台收集"))
        XCTAssertTrue(pausedTitles.contains("快速记录…"))
        XCTAssertTrue(pausedTitles.contains("保存当前剪贴板"))
        XCTAssertTrue(pausedTitles.contains("搜索资料库…"))

        runtime.setCaptureEnabled(true)
        let activeMenu = DockMenuController.shared.makeMenu(store: store, runtime: runtime)
        XCTAssertTrue(activeMenu.items.map(\.title).contains("暂停后台收集"))
    }

    @MainActor
    func testFinderRightClickServiceIgnoresTextAndWebSelections() {
        let textPasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        textPasteboard.clearContents()
        textPasteboard.setString("网页中选中的一段文字", forType: .string)
        XCTAssertTrue(SystemServicesProvider.fileURLs(from: textPasteboard).isEmpty)

        let urlPasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))
        urlPasteboard.clearContents()
        urlPasteboard.setString("https://example.com/selected", forType: .string)
        XCTAssertTrue(SystemServicesProvider.fileURLs(from: urlPasteboard).isEmpty)
    }

    @MainActor
    func testLegacyAmbientSourceBackfillsExplicitSourceApplication() {
        let item = CaptureItem(kind: .text, title: "来自浏览器", source: "无感记录 · Safari")
        let store = CaptureStore(testItems: [item])

        XCTAssertEqual(store.items.first?.sourceApplication, "Safari")
        XCTAssertEqual(store.search("Safari").first?.id, item.id)
    }

    @MainActor
    func testRevealInAllCreatesScrollFocusRequest() {
        let item = CaptureItem(kind: .text, title: "目标", source: "测试")
        let store = CaptureStore(testItems: [item])

        store.revealInAll(item.id)

        XCTAssertEqual(store.category, .all)
        XCTAssertEqual(store.selectedItemID, item.id)
        XCTAssertEqual(store.focusRequest?.itemID, item.id)
    }
}
