import SwiftUI

struct CredentialCaptureSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: CaptureStore
    let item: CaptureItem?
    let onSaved: () -> Void

    @State private var recordType: CredentialRecordType
    @State private var platformSelection: String
    @State private var customPlatform: String
    @State private var username: String
    @State private var password = ""
    @State private var loginURL: String
    @State private var providerSelection: String
    @State private var customProvider: String
    @State private var apiBaseURL: String

    init(store: CaptureStore, item: CaptureItem? = nil, onSaved: @escaping () -> Void = {}) {
        self.store = store
        self.item = item
        self.onSaved = onSaved

        let type = item?.credentialType ?? .account
        let currentPlatform = item.map(CredentialPlatformCatalog.displayName(for:))
        let isPlatformPreset = CredentialPlatformCatalog.preset(named: currentPlatform) != nil
        let currentProvider = item.map(LLMProviderCatalog.displayName(for:))
        let isProviderPreset = LLMProviderCatalog.preset(named: currentProvider) != nil

        _recordType = State(initialValue: type)
        _platformSelection = State(initialValue: isPlatformPreset ? (currentPlatform ?? "") : (currentPlatform == nil ? "" : CredentialPlatformCatalog.customSelection))
        _customPlatform = State(initialValue: isPlatformPreset ? "" : (currentPlatform == "未指定平台" ? "" : currentPlatform ?? ""))
        _username = State(initialValue: item?.username ?? "")
        _loginURL = State(initialValue: item?.loginURL ?? "")
        _providerSelection = State(initialValue: isProviderPreset ? (currentProvider ?? "") : (currentProvider == nil ? "" : LLMProviderCatalog.customSelection))
        _customProvider = State(initialValue: isProviderPreset ? "" : (currentProvider == "OpenAI 兼容 / 待确认" ? "" : currentProvider ?? ""))
        _apiBaseURL = State(initialValue: item?.apiBaseURL ?? "")
    }

    private var resolvedPlatform: String {
        platformSelection == CredentialPlatformCatalog.customSelection
            ? customPlatform.trimmingCharacters(in: .whitespacesAndNewlines)
            : platformSelection
    }

    private var resolvedProvider: String {
        providerSelection == LLMProviderCatalog.customSelection
            ? customProvider.trimmingCharacters(in: .whitespacesAndNewlines)
            : providerSelection
    }

    private var canSave: Bool {
        switch recordType {
        case .account:
            !resolvedPlatform.isEmpty && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .apiKey:
            !resolvedProvider.isEmpty
                && !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && normalizedAPIURL != nil
                && (item != nil || !password.isEmpty)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("记录类型", selection: $recordType) {
                        ForEach(CredentialRecordType.allCases) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if recordType == .account {
                        accountPlatformSection
                        accountSection
                        webSection
                    } else {
                        providerSection
                        apiKeySection
                        apiEndpointSection
                    }
                    privacyNote
                }
                .padding(24)
            }

            Divider()
            footer
        }
        .frame(width: 580, height: 680)
        .background(.regularMaterial)
        .onChange(of: platformSelection) { _, selection in
            guard let preset = CredentialPlatformCatalog.preset(named: selection),
                  loginURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            loginURL = preset.loginURL
        }
        .onChange(of: providerSelection) { _, selection in
            guard let preset = LLMProviderCatalog.preset(named: selection) else { return }
            apiBaseURL = preset.baseURL
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            CredentialPlatformMark(
                platform: recordType == .apiKey ? resolvedProvider : resolvedPlatform,
                credentialType: recordType,
                size: 48
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(item == nil ? (recordType == .apiKey ? "记录 LLM API 密钥" : "记录网站账号") : "编辑安全记录")
                    .font(.title3.weight(.semibold))
                Text(recordType == .apiKey ? "识别服务商，保存密钥，并配置调用地址" : "关联平台、账号与对应的登录网页")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var accountPlatformSection: some View {
        formSection(title: "所属平台", subtitle: "可从常见平台中选择，也可以创建自己的平台名称") {
            Picker("平台", selection: $platformSelection) {
                Text("选择平台…").tag("")
                ForEach(CredentialPlatformCatalog.presets) { preset in
                    Label(preset.name, systemImage: preset.systemImage).tag(preset.name)
                }
                Divider()
                Label("自定义平台", systemImage: "plus.square.dashed").tag(CredentialPlatformCatalog.customSelection)
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if platformSelection == CredentialPlatformCatalog.customSelection {
                TextField("例如：公司后台、社区论坛", text: $customPlatform)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var providerSection: some View {
        formSection(title: "LLM 服务商", subtitle: "常见服务商会自动带出官方 Base URL，也可创建兼容服务") {
            Picker("服务商", selection: $providerSelection) {
                Text("选择服务商…").tag("")
                ForEach(LLMProviderCatalog.presets) { preset in
                    Label(preset.name, systemImage: preset.systemImage).tag(preset.name)
                }
                Divider()
                Label("自定义 / OpenAI 兼容", systemImage: "plus.square.dashed").tag(LLMProviderCatalog.customSelection)
            }
            .pickerStyle(.menu)
            .labelsHidden()

            if providerSelection == LLMProviderCatalog.customSelection {
                TextField("例如：公司网关、LocalAI", text: $customProvider)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }

    private var accountSection: some View {
        formSection(title: "账号与密码", subtitle: item == nil ? "密码不会写入记录正文" : "密码留空表示保持原密码不变") {
            labeledField("账号", icon: "person") {
                TextField("邮箱、用户名或手机号", text: $username)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.username)
            }

            labeledField("密码", icon: "key") {
                SecureField(item == nil ? "可选，将安全存入钥匙串" : "留空则不修改", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
            }
        }
    }

    private var apiKeySection: some View {
        formSection(title: "密钥信息", subtitle: item == nil ? "密钥为必填，保存后不会进入正文" : "密钥留空表示保持原值不变") {
            labeledField("名称", icon: "tag") {
                TextField("例如：默认密钥、生产环境", text: $username)
                    .textFieldStyle(.roundedBorder)
            }
            labeledField("API Key", icon: "key.horizontal") {
                SecureField(item == nil ? "粘贴 API Key" : "留空则不修改", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.password)
            }
        }
    }

    private var webSection: some View {
        formSection(title: "登录网页", subtitle: "可选；关联后卡片可直接打开对应的 Web 登录页") {
            labeledField("地址", icon: "globe") {
                TextField("https://example.com/login", text: $loginURL)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
            }
            if let host = normalizedLoginURL?.host(percentEncoded: false) {
                Label("将绑定到 \(host)", systemImage: "link.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
    }

    private var apiEndpointSection: some View {
        formSection(title: "API 调用地址", subtitle: "Base URL 可随时修改；兼容代理、本机模型与企业网关") {
            labeledField("Base URL", icon: "network") {
                TextField("https://api.example.com/v1", text: $apiBaseURL)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.URL)
            }
            if let host = normalizedAPIURL?.host(percentEncoded: false) {
                HStack {
                    Label(host, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Text("仅保存配置，不会自动发送密钥")
                        .foregroundStyle(.secondary)
                }
                .font(.caption2)
            }
        }
    }

    private var privacyNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 3) {
                Text("本机安全存储")
                    .font(.caption.weight(.semibold))
                Text(recordType == .apiKey
                    ? "服务商、密钥名称和 Base URL 进入\(AppBrand.displayName)索引；API Key 只进入 macOS 钥匙串，不参与搜索，也不会出现在摘要或正文中。"
                    : "平台、账号和登录地址进入\(AppBrand.displayName)索引；密码只进入 macOS 钥匙串，不参与搜索，也不会出现在导出的记录正文中。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.16)))
    }

    private var footer: some View {
        HStack {
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(item == nil ? (recordType == .apiKey ? "安全保存密钥" : "保存账号") : "保存修改") { save() }
                .buttonStyle(.borderedProminent)
                .tint(SuijiTheme.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private var normalizedLoginURL: URL? { normalizedURL(loginURL) }
    private var normalizedAPIURL: URL? { normalizedURL(apiBaseURL) }

    private func normalizedURL(_ value: String) -> URL? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        let normalized = clean.hasPrefix("http://") || clean.hasPrefix("https://") ? clean : "https://" + clean
        guard let url = URL(string: normalized), url.host() != nil else { return nil }
        return url
    }

    private func formSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(15)
        .background(.background.opacity(0.48), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(SuijiTheme.divider))
    }

    private func labeledField<Content: View>(
        _ label: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 11) {
            Label(label, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            content()
        }
    }

    private func save() {
        if recordType == .apiKey {
            if let item {
                store.updateAPIKey(
                    id: item.id,
                    provider: resolvedProvider,
                    keyLabel: username,
                    apiKey: password,
                    baseURL: apiBaseURL
                )
            } else {
                store.captureAPIKey(
                    provider: resolvedProvider,
                    keyLabel: username,
                    apiKey: password,
                    baseURL: apiBaseURL
                )
            }
        } else if let item {
            store.updateCredential(
                id: item.id,
                platform: resolvedPlatform,
                username: username,
                password: password,
                loginURL: loginURL
            )
        } else {
            store.captureCredential(
                platform: resolvedPlatform,
                username: username,
                password: password,
                loginURL: loginURL
            )
        }
        onSaved()
        dismiss()
    }
}

struct CredentialPlatformMark: View {
    let platform: String?
    var credentialType: CredentialRecordType = .account
    var size: CGFloat = 46

    private var systemImage: String {
        credentialType == .apiKey
            ? LLMProviderCatalog.systemImage(for: platform)
            : CredentialPlatformCatalog.systemImage(for: platform)
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: credentialType == .apiKey
                        ? [Color.indigo, Color.cyan.opacity(0.76)]
                        : [SuijiTheme.accent, SuijiTheme.accent.opacity(0.68)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: size * 0.25)
            )
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.25)
                    .stroke(.white.opacity(0.18))
            }
    }
}
