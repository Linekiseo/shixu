import SwiftUI

struct SettingsView: View {
    @AppStorage("autoCaptureClipboard") private var autoCaptureClipboard = true
    @AppStorage("autoIndexWatchedFolders") private var autoIndexWatchedFolders = true
    @AppStorage("fileStorageMode") private var fileStorageMode = FileStorageMode.linked.rawValue
    @AppStorage("deepSeekAISearchBaseURL") private var deepSeekBaseURL = DeepSeekAISearchService.defaultBaseURL
    @State private var cacheCleared = false
    @State private var deepSeekKeyDraft = ""
    @State private var deepSeekConfigured = false
    @State private var isSavingDeepSeekKey = false
    @State private var deepSeekStatus: String?
    @ObservedObject private var runtime = CaptureRuntimeController.shared

    var body: some View {
        Form {
            Section("收集") {
                Toggle("运行后台收集", isOn: Binding(
                    get: { runtime.isCaptureEnabled },
                    set: { runtime.setCaptureEnabled($0) }
                ))
                Toggle("自动保存剪贴板变化", isOn: $autoCaptureClipboard)
                Toggle("自动索引监测文件夹变化", isOn: $autoIndexWatchedFolders)
                Text(runtime.isCaptureEnabled ? "正在读取新的剪贴板与监测文件夹变化。" : "已暂停读取新的系统变化；手动记录、截屏和保存当前剪贴板仍可使用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("后台收集运行时，疑似账号、密码和验证码始终进入待确认，不会静默保存。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("文件") {
                Picker("文件保存方式", selection: $fileStorageMode) {
                    ForEach(FileStorageMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                if let mode = FileStorageMode(rawValue: fileStorageMode) {
                    Text(mode.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("系统联动") {
                LabeledContent("Dock 图标控制", value: "右键打开")
                LabeledContent("全局快速记录", value: "⌘ ⇧ Space")
                LabeledContent("访达右键收集", value: "多选文件与文件夹")
                Text("在访达中选中一个或多个项目，右键打开“服务”，选择“存入拾序”。网页和文字继续由剪贴板监测接收。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("账号密码", value: "macOS 钥匙串")
                LabeledContent("资料位置", value: "~/Library/Application Support/Suiji")
            }

            Section("AI 辅助搜索") {
                TextField("DeepSeek Base URL", text: $deepSeekBaseURL)
                    .textContentType(.URL)
                SecureField(deepSeekConfigured ? "已存入钥匙串；输入新值可替换" : "DeepSeek API Key", text: $deepSeekKeyDraft)
                HStack {
                    Label(deepSeekConfigured ? "API Key 已安全配置" : "尚未配置 API Key", systemImage: deepSeekConfigured ? "checkmark.shield.fill" : "key")
                        .foregroundStyle(deepSeekConfigured ? Color.green : Color.secondary)
                    Spacer()
                    Button(deepSeekConfigured ? "更新密钥" : "保存密钥") {
                        isSavingDeepSeekKey = true
                        let draft = deepSeekKeyDraft
                        Task {
                            if await DeepSeekAISearchService.saveAPIKeyAsync(draft) {
                                deepSeekKeyDraft = ""
                                deepSeekConfigured = true
                                deepSeekStatus = "已保存到 macOS 钥匙串"
                            } else {
                                deepSeekStatus = "请输入有效的 API Key"
                            }
                            isSavingDeepSeekKey = false
                        }
                    }
                    .disabled(deepSeekKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSavingDeepSeekKey)
                }
                if let deepSeekStatus {
                    Text(deepSeekStatus).font(.caption).foregroundStyle(.secondary)
                }
                Text("AI 只接收你主动提交的查询，用于理解时间、类型和同义词；资料标题、正文、附件及账号密钥不会上传。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("网页预览") {
                LabeledContent("加载策略", value: "可见时加载 · 最多 3 个并发")
                LabeledContent("登录会话", value: "按根网站共享")
                Text("网页缩略图会缓存在本机；快速滚动或离开界面时，尚未完成的加载会自动取消。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("网页归档使用独立的 WebKit 站点会话；例如 linux.do 登录一次后，其帖子会复用该登录状态。密码不会写入拾序记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(cacheCleared ? "缓存已清除" : "清除网页预览缓存", systemImage: cacheCleared ? "checkmark" : "trash") {
                    WebPreviewService.shared.clearCache()
                    WebArchiveThumbnailService.shared.clearCache()
                    cacheCleared = true
                }
                .disabled(cacheCleared)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 660)
        .navigationTitle("\(AppBrand.displayName)设置")
        .task { deepSeekConfigured = await DeepSeekAISearchService.configurationStatus() }
    }
}
