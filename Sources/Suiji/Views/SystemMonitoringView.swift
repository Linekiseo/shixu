import AppKit
import SwiftUI

struct SystemMonitoringView: View {
    @ObservedObject var store: CaptureStore
    @ObservedObject private var folderMonitor = FolderMonitorService.shared
    @ObservedObject private var runtime = CaptureRuntimeController.shared
    @AppStorage("autoCaptureClipboard") private var autoCaptureClipboard = true
    @AppStorage("autoIndexWatchedFolders") private var autoIndexWatchedFolders = true

    private var signalSections: [SystemSignalTimelineSection] {
        SystemSignalTimelineSection.sections(from: Array(store.systemSignals.prefix(30)))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    ambientControls
                    watchedFolders
                    recentSignals
                }
                .padding(24)
            }
        }
        .navigationSplitViewColumnWidth(min: 500, ideal: 680)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("系统监测")
                    .font(SuijiTheme.titleFont)
                Text("在后台接住信息，不打断当前工作")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("后台收集", isOn: Binding(
                get: { runtime.isCaptureEnabled },
                set: { runtime.setCaptureEnabled($0) }
            ))
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
    }

    private var ambientControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "无感记录规则", detail: "敏感信息永远需要确认")

            HStack(spacing: 12) {
                MonitorRuleCard(
                    icon: "doc.on.clipboard",
                    title: "剪贴板",
                    detail: "文字、网页与图片自动归类",
                    enabled: $autoCaptureClipboard
                )
                MonitorRuleCard(
                    icon: "folder.badge.gearshape",
                    title: "监测文件夹",
                    detail: "新增和修改文件自动建立引用",
                    enabled: $autoIndexWatchedFolders
                )
                VStack(alignment: .leading, spacing: 9) {
                    Image(systemName: "lock.shield")
                        .font(.title3)
                        .foregroundStyle(SuijiTheme.accent)
                    Text("账号与密码").font(.headline)
                    Text("识别后进入待确认，不静默保存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label("强制保护", systemImage: "checkmark.shield")
                        .font(.caption2)
                        .foregroundStyle(SuijiTheme.accent)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
                .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(SuijiTheme.divider))
            }
            .disabled(!runtime.isCaptureEnabled)
        }
    }

    private var watchedFolders: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionTitle(title: "监测文件夹", detail: "只建立本地引用，默认不复制文件")
                Spacer()
                Button("添加文件夹", systemImage: "folder.badge.plus") { chooseFolder() }
                    .buttonStyle(.bordered)
            }

            if folderMonitor.folders.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("还没有监测目录").font(.caption.weight(.semibold))
                        Text("可以添加下载、桌面或工作资料夹；已有文件只建立快照，之后的变化才会被记录。")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            } else {
                VStack(spacing: 0) {
                    ForEach(folderMonitor.folders) { folder in
                        HStack(spacing: 11) {
                            Image(systemName: "folder.fill").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(folder.displayName).font(.caption.weight(.semibold))
                                Text(folder.path).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                            }
                            Spacer()
                            Text(folder.isEnabled ? "监测中" : "已暂停")
                                .font(.caption2)
                                .foregroundStyle(folder.isEnabled ? .green : .secondary)
                            Toggle("", isOn: Binding(
                                get: { folder.isEnabled },
                                set: { folderMonitor.setEnabled($0, for: folder.id) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            Button {
                                folderMonitor.removeFolder(folder.id)
                            } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 10)
                        .overlay(alignment: .bottom) { Divider() }
                    }
                }
            }
        }
    }

    private var recentSignals: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "最近系统信号", detail: "\(store.systemSignals.filter { $0.state == .pending }.count) 条待确认")

            if store.systemSignals.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundStyle(.secondary)
                    Text("监测到的剪贴板、文件夹和系统服务事件会按日期出现在这里。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(signalSections) { section in
                        VStack(alignment: .leading, spacing: 0) {
                            SignalTimelineHeader(section: section)
                            ForEach(section.signals) { signal in
                                HStack(spacing: 11) {
                                    Image(systemName: signal.source.systemImage)
                                        .foregroundStyle(signal.kind == .credential ? SuijiTheme.accent : .secondary)
                                        .frame(width: 22)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(signal.title).font(.caption.weight(.semibold)).lineLimit(1)
                                        Text([signal.sourceApplication, signal.detail].compactMap { $0 }.joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Text(signal.createdAt.suijiTime).font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                                    if signal.state == .pending {
                                        Button("忽略") { store.ignore(signalID: signal.id) }.buttonStyle(.borderless)
                                        Button("收下") { store.capture(signalID: signal.id) }.buttonStyle(.bordered)
                                    } else {
                                        Label(signal.state == .captured ? "已归档" : "已忽略", systemImage: signal.state == .captured ? "checkmark" : "minus")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 10)
                                .overlay(alignment: .bottom) { Divider() }
                            }
                        }
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "开始监测"
        if panel.runModal() == .OK {
            panel.urls.forEach(folderMonitor.addFolder)
        }
    }
}

private struct SignalTimelineHeader: View {
    let section: SystemSignalTimelineSection

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
            Text(section.title)
                .font(.caption.weight(.semibold))
            Rectangle()
                .fill(Color.green.opacity(0.16))
                .frame(height: 1)
            Text(section.timeRange)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)
            Text("\(section.signals.count) 条")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }
}

private struct SectionTitle: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

private struct MonitorRuleCard: View {
    let icon: String
    let title: String
    let detail: String
    @Binding var enabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: icon).font(.title3).foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(detail).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Toggle("自动收下", isOn: $enabled)
                .font(.caption2)
                .toggleStyle(.switch)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(SuijiTheme.divider))
    }
}
