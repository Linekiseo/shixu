import AppKit
import SwiftUI

struct CredentialVaultCard: View {
    @ObservedObject var store: CaptureStore
    let item: CaptureItem
    var compactLayout = false
    @State private var copiedEndpoint = false

    private var isAPIKey: Bool { item.credentialType == .apiKey }
    private var platform: String {
        isAPIKey ? LLMProviderCatalog.displayName(for: item) : CredentialPlatformCatalog.displayName(for: item)
    }

    var body: some View {
        Group {
            if compactLayout { compactBody }
            else { regularBody }
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor).opacity(0.92),
                    (isAPIKey ? Color.indigo : SuijiTheme.accent).opacity(0.055)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay(RoundedRectangle(cornerRadius: 14).stroke((isAPIKey ? Color.indigo : SuijiTheme.accent).opacity(0.21)))
    }

    private var regularBody: some View {
        HStack(spacing: 0) {
            VStack(spacing: 9) {
                CredentialPlatformMark(platform: platform, credentialType: isAPIKey ? .apiKey : .account, size: 52)
                Text(isAPIKey ? "LLM API" : platform.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(isAPIKey ? Color.indigo : Color.secondary)
                    .lineLimit(1)
            }
            .frame(width: 88)

            Rectangle()
                .fill((isAPIKey ? Color.indigo : SuijiTheme.accent).opacity(0.16))
                .frame(width: 1)
                .padding(.vertical, 14)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(platform)
                            .font(.custom("Songti SC", size: 17).weight(.semibold))
                        Text(statusLine)
                            .font(.caption2)
                            .foregroundStyle(statusColor)
                    }
                    .lineLimit(1)
                    Spacer()
                    Label("钥匙串", systemImage: "checkmark.shield.fill")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.green)
                }

                HStack(spacing: 22) {
                    credentialColumn(label: isAPIKey ? "密钥名称" : "账号", value: item.username ?? "待补充")
                    credentialColumn(label: isAPIKey ? "API KEY" : "密码", value: "••••••••••")
                }

                HStack(spacing: 8) {
                    endpointAction
                    Spacer()
                    Text(item.createdAt.suijiDayLabel)
                    Button { store.toggleFavorite(item.id) } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(15)
        }
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                CredentialPlatformMark(platform: platform, credentialType: isAPIKey ? .apiKey : .account, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(platform)
                        .font(.custom("Songti SC", size: 17).weight(.semibold))
                        .lineLimit(2)
                    Text(statusLine)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }
                Spacer(minLength: 4)
                Image(systemName: "checkmark.shield.fill")
                    .foregroundStyle(.green)
                    .help("密钥保存在 macOS 钥匙串")
            }
            .padding(14)

            Rectangle()
                .fill((isAPIKey ? Color.indigo : SuijiTheme.accent).opacity(0.14))
                .frame(height: 1)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 18) {
                    credentialColumn(label: isAPIKey ? "密钥名称" : "账号", value: item.username ?? "待补充")
                    credentialColumn(label: isAPIKey ? "API KEY" : "密码", value: "••••••••••")
                }

                HStack(spacing: 7) {
                    endpointAction
                    Spacer(minLength: 4)
                    Text(item.createdAt.suijiDayLabel)
                    Button { store.toggleFavorite(item.id) } label: {
                        Image(systemName: item.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(item.isFavorite ? Color.yellow : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLine: String {
        if isAPIKey { return item.apiBaseURL == nil ? "Base URL 待配置" : "调用地址已配置" }
        return item.loginURL == nil ? "本机账号" : "已绑定 Web 登录"
    }

    private var statusColor: Color {
        if isAPIKey { return item.apiBaseURL == nil ? .orange : .indigo }
        return item.loginURL == nil ? .secondary : .blue
    }

    @ViewBuilder
    private var endpointAction: some View {
        if isAPIKey, let baseURL = item.apiBaseURL {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(baseURL, forType: .string)
                copiedEndpoint = true
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    copiedEndpoint = false
                }
            } label: {
                Label(item.domain ?? baseURL, systemImage: copiedEndpoint ? "checkmark" : "network")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.indigo)
            .help("复制 Base URL")
        } else if isAPIKey {
            Label("需要配置 Base URL", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else if let domain = item.domain, let loginURL = item.loginURL {
            Button {
                if let url = URL(string: loginURL) { NSWorkspace.shared.open(url) }
            } label: {
                Label(domain, systemImage: "globe")
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
        } else {
            Label("仅本机保存", systemImage: "macbook")
        }
    }

    private func credentialColumn(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(.tertiary)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
        }
    }
}
