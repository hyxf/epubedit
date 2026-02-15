import Foundation

enum EpubError: LocalizedError {
  case fileNotFound(path: String)
  case invalidEpubStructure(reason: String)
  case opfParsingFailed(details: String)
  case opfSaveFailed(details: String)
  case coverImageMissing(path: String)
  case invalidCoverFormat(format: String)
  case coverCopyFailed(details: String)
  case outputExists
  case unzipFailed(details: String)
  case zipFailed(details: String)

  var errorDescription: String? {
    switch self {
    case .fileNotFound(let path):
      return "❌ 错误：找不到文件\n   路径: \(path)\n   提示: 请检查文件路径是否正确"

    case .invalidEpubStructure(let reason):
      return "❌ 无效的 EPUB 结构\n   原因: \(reason)\n   提示: 该文件可能已损坏或不是有效的 EPUB 文件"

    case .opfParsingFailed(let details):
      return "❌ 错误：无法解析 OPF 元数据文件\n   详情: \(details)\n   提示: EPUB 的元数据文件可能格式错误"

    case .opfSaveFailed(let details):
      return "❌ 错误：无法保存 OPF 元数据文件\n   详情: \(details)\n   提示: 可能是权限问题或磁盘空间不足"

    case .coverImageMissing(let path):
      return "❌ 错误：找不到封面图片文件\n   路径: \(path)\n   提示: 请检查封面图片路径是否正确"

    case .invalidCoverFormat(let format):
      return "❌ 错误：不支持的封面图片格式\n   格式: .\(format)\n   提示: 仅支持 .jpg, .jpeg, .png 格式"

    case .coverCopyFailed(let details):
      return "❌ 错误：复制封面图片失败\n   详情: \(details)"

    case .outputExists:
      return """
        ❌ 错误：输出文件已存在
           提示: 使用 --overwrite 选项强制覆盖现有文件
           示例: epubedit --file input.epub --title "新标题" --overwrite
        """

    case .unzipFailed(let details):
      return "❌ 错误：EPUB 解压失败\n   详情: \(details)\n   提示: 文件可能已损坏或不是有效的 ZIP 格式"

    case .zipFailed(let details):
      return "❌ 错误：EPUB 打包失败\n   详情: \(details)\n   提示: 可能是磁盘空间不足或权限问题"
    }
  }
}
