# 参与拾序

感谢你的帮助。建议先通过 Issue 描述问题或改进目标，再提交范围清晰的 Pull Request。

## 开发与验证

使用 macOS 和支持 Swift 6 的工具链：

```sh
swift build
swift test
for script in script/*.sh; do bash -n "$script"; done
```

需要查看原生界面时，运行 `./script/build_and_run.sh`。构建脚本会关闭已运行的同名应用。

- 保持 SwiftUI 视图与数据逻辑分离；只在必要时引入 AppKit 桥接。
- 修改记录合并、排序、去重或持久化逻辑时，补充对应回归测试。
- UI、拖拽及系统联动修改应说明人工验证情况，不要把单元测试通过等同于完整 UI 验证。
- 使用 `CaptureStore(testItems:)` 和临时目录构造测试，不要操作真实资料库或真实钥匙串凭据。
- 不要提交构建缓存、安装包、个人截图、`.env`、证书、Cookie 或真实 API Key。

## 报告问题

请提供 macOS 版本、应用版本或提交编号、复现步骤、期望行为与实际结果。附图前遮盖个人内容；提供文件时仅使用可公开的最小测试样本。

安全问题请按 [SECURITY.md](SECURITY.md) 私下报告，不要先公开漏洞利用细节。

你提交的贡献将使用本项目的 MIT 许可证分发。
