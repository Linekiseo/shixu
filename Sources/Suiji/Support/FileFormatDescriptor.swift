import Foundation
import UniformTypeIdentifiers

struct FileFormatDescriptor: Hashable, Sendable {
    let formatName: String
    let category: String
    let systemImage: String
    let previewDescription: String

    static func describe(url: URL?, fallbackExtension: String?) -> FileFormatDescriptor {
        let fileExtension = (url?.pathExtension.isEmpty == false ? url?.pathExtension : fallbackExtension)?
            .lowercased() ?? ""
        let type = UTType(filenameExtension: fileExtension)

        if type?.conforms(to: .pdf) == true {
            return .init(formatName: "PDF", category: "便携文档", systemImage: "doc.richtext.fill", previewDescription: "支持整页浏览与缩放")
        }
        if type?.conforms(to: .plainText) == true || ["md", "markdown", "json", "yaml", "yml", "xml", "csv", "log"].contains(fileExtension) {
            return .init(formatName: fileExtension.uppercased().nonEmpty ?? "TEXT", category: "文本与代码", systemImage: "text.page.fill", previewDescription: "支持系统文本预览")
        }
        if type?.conforms(to: .image) == true {
            return .init(formatName: fileExtension.uppercased().nonEmpty ?? "IMAGE", category: "图像", systemImage: "photo.fill", previewDescription: "支持原始画面预览")
        }
        if type?.conforms(to: .audio) == true {
            return .init(formatName: fileExtension.uppercased().nonEmpty ?? "AUDIO", category: "音频", systemImage: "waveform", previewDescription: "支持系统播放器预览")
        }
        if type?.conforms(to: .movie) == true || type?.conforms(to: .video) == true {
            return .init(formatName: fileExtension.uppercased().nonEmpty ?? "VIDEO", category: "视频", systemImage: "play.rectangle.fill", previewDescription: "支持系统播放器预览")
        }
        if type?.conforms(to: .archive) == true {
            return .init(formatName: fileExtension.uppercased().nonEmpty ?? "ARCHIVE", category: "压缩包", systemImage: "archivebox.fill", previewDescription: "显示压缩包内容摘要")
        }

        switch fileExtension {
        case "doc", "docx", "pages", "rtf", "odt":
            return .init(formatName: fileExtension.uppercased(), category: "文字文稿", systemImage: "doc.text.fill", previewDescription: "通过系统 Quick Look 预览")
        case "xls", "xlsx", "numbers", "ods":
            return .init(formatName: fileExtension.uppercased(), category: "电子表格", systemImage: "tablecells.fill", previewDescription: "通过系统 Quick Look 预览")
        case "ppt", "pptx", "key", "odp":
            return .init(formatName: fileExtension.uppercased(), category: "演示文稿", systemImage: "rectangle.on.rectangle.angled", previewDescription: "通过系统 Quick Look 预览")
        case "html", "htm", "webarchive":
            return .init(formatName: fileExtension.uppercased(), category: "网页文件", systemImage: "globe", previewDescription: "通过系统 Quick Look 预览")
        default:
            return .init(
                formatName: fileExtension.uppercased().nonEmpty ?? "FILE",
                category: type?.localizedDescription ?? "通用文件",
                systemImage: "doc.fill",
                previewDescription: "使用 macOS Quick Look 或已安装的格式扩展"
            )
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
