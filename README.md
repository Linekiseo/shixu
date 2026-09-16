<p align="center">
  <img src="Assets/AppIcon/app-icon-1024.png" width="112" alt="拾序图标">
</p>

# 拾序 · Shixu

随手收集，按自己的方式找回来。

拾序是一款本地优先的 **macOS 原生资料收集应用**，用于整理文字、截图、网页、文件、账号和 API 配置。它使用 SwiftUI 与 AppKit 构建，不是网页套壳，也不需要部署后端。

[![macOS CI](https://github.com/Linekiseo/shixu/actions/workflows/ci.yml/badge.svg)](https://github.com/Linekiseo/shixu/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

项目处于早期迭代阶段。欢迎反馈问题和参与改进；涉及重要资料时，请保留原文件及自己的备份。

## 可以做什么

- **随手收集**：剪贴板监测、拖拽导入、全局快速记录、交互式截屏，以及访达“服务”中的文件导入。
- **按内容呈现**：文字、图片、网页、文件、账号使用不同卡片；长文本可识别 Markdown 等格式，生成对应文件。
- **预览与归档**：图片缩放、文档预览、网页缩略图和本机网页存档；登录网页可在应用内建立站点会话。
- **自由组合**：拖拽关联卡片、向已有组合继续添加内容、调整成员顺序，也可将 URL 合入 API 配置。
- **时间浏览**：全部记录、类型资料库、组合视图，以及年、月、周、日层级的时间浏览。
- **本机搜索**：关键词、类型、时间筛选；可选 DeepSeek 辅助理解自然语言查询，再在本机检索。
- **系统控制**：通过 Dock 图标右键菜单或设置，启动、暂停后台收集。

## 环境要求

- macOS 14 或更高版本。
- 支持 Swift 6 的 Xcode 或 Command Line Tools；本仓库采用 Swift Package Manager。
- 支持 Apple 芯片与 Intel Mac；不支持在 Windows、Linux 或浏览器中运行。

目前没有第三方 Swift Package 依赖。Swift 包名、可执行文件名和数据目录仍使用 `Suiji`，以兼容早期版本；应用显示名称为“拾序”。

## 从源码运行

```sh
git clone https://github.com/Linekiseo/shixu.git
cd shixu
swift build
swift test
./script/build_and_run.sh
```

最后一条命令会生成 `dist/拾序.app` 并打开它。该脚本会先关闭已运行的同名应用，再重建应用包；记录数据不保存在应用包中。

如只需构建应用包，不启动界面：

```sh
./script/build_and_run.sh --build-only
```

完整的系统联动功能应通过 `.app` 使用，而不是直接运行构建目录里的裸可执行文件。

## 基本操作

- `⌘ ⇧ Space`：全局快速记录。
- `⌘ K`：在应用内打开搜索。
- `⌘ ⇧ V`：保存当前剪贴板。
- 访达中多选文件，右键 → 服务 → **存入拾序**。
- 将一张记录卡片拖到另一张上创建组合；拖到已有组合标题区追加，拖到成员卡片上插入。
- 右键点击桌面底部 Dock 中的应用图标，可暂停或恢复后台收集。

首次运行默认开启后台剪贴板收集；文件夹监测只针对自行添加的目录。若不希望自动记录，请先暂停后台收集，或在设置中关闭对应选项。

## AI 辅助搜索（可选）

在“设置 → AI 辅助搜索”中填写自己的 API Key 和 HTTPS Base URL。未配置时仍可使用普通本机搜索。

API Key 存入 macOS 钥匙串。AI 请求发送的是你主动提交的查询文字、日期和查询解析提示，不附带资料库标题、正文、附件或已保存凭据。**如果查询本身包含秘密，这段文字仍会发送给所配置的服务**，请不要把密钥或密码输入搜索问题。

当前使用 DeepSeek 的接口约定，默认服务地址为 `https://api.deepseek.com`；服务可用性、模型支持及费用由服务提供方决定。项目不附带共享密钥。

## 数据与隐私

- 记录及附件位于 `~/Library/Application Support/Suiji`；账号密码和 API 密钥字段使用系统钥匙串存储。
- 标题、用户名、链接、标签、正文等普通记录元数据 **不是加密数据库**。文件压缩也不等同于加密。
- 文件默认保存为本机引用，不复制原文件；可选择 LZFSE 压缩备份。链接模式下移动或删除原文件可能影响访问。
- 网页预览和归档会访问原网站，并可能加载该网站的第三方资源；站点登录会话由 WebKit 管理。
- 已识别的敏感剪贴板内容会进入待确认流程，但自动识别不能保证覆盖所有秘密格式。处理敏感信息时请暂停自动收集。
- 仓库不包含个人记录、真实账号、API Key、浏览器会话、网页存档或本机工作截图。

详见 [安全说明](SECURITY.md)。

## 构建可分发安装包

```sh
./script/package_distribution.sh
```

脚本会构建 arm64 与 x86_64，生成通用 `.app`、压缩 DMG 和 SHA-256 校验文件，输出到 `dist/`。这些生成物不会提交到 Git。

默认使用本机临时签名，**不代表已经通过 Apple Developer ID 签名或公证**。正式分发可使用本机已有的签名身份和 `notarytool` 配置，传入 `SIGN_IDENTITY`、`NOTARY_PROFILE`；不要把证书、私钥或账号凭据提交到仓库。

## 代码结构

```text
Sources/Suiji/
  App/          应用入口与系统命令
  Models/       记录、分类、时间与组合模型
  Stores/       状态、整理、检索和持久化调度
  Services/     剪贴板、文件、网页、钥匙串和 AI 接口
  Support/      布局、拖放、类型识别与展示辅助
  Views/        原生界面与预览
Tests/          SwiftPM 回归测试
Assets/         应用图标
script/         应用构建与打包
distribution/   安装说明
```

## 当前边界

- 网页存档效果受登录状态、动态资源、反爬机制和网站实现影响，不能保证每个网站完整离线还原。
- 文档格式的预览能力依赖 macOS 及已安装的预览支持，不承诺任意格式都可渲染。
- 自动测试覆盖内容识别、记录组合、排序、搜索和存档等逻辑；不替代鼠标拖拽、系统权限和复杂网站的人工验证。
- 目前没有云同步、团队共享或跨平台版本。

## 参与与许可

欢迎提交 [Issue](https://github.com/Linekiseo/shixu/issues) 或 Pull Request。开始前请阅读 [贡献指南](CONTRIBUTING.md)，不要在公开反馈中附上真实账号、密钥或私人记录。

本项目采用 [MIT License](LICENSE)。
