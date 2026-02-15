//
// EpubProcessor.swift
// epubedit
// 完全符合 EPUB 规范的版本
//

import Foundation
import ZIPFoundation

class EpubProcessor {
  let sourcePath: String
  let outputPath: String?
  let overwrite: Bool

  init(sourcePath: String, outputPath: String?, overwrite: Bool) {
    self.sourcePath = sourcePath
    self.outputPath = outputPath
    self.overwrite = overwrite
  }

  func run(title: String?, author: String?, publisher: String?, language: String?, identifier: String?, description: String?, coverPath: String?) throws {
    let fileManager = FileManager.default
    let sourceURL = URL(fileURLWithPath: sourcePath)
    let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)

    try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

    var cleanupSuccess = false
    defer {
      if !cleanupSuccess {
        for attempt in 1...3 {
          if (try? fileManager.removeItem(at: tempDir)) != nil {
            cleanupSuccess = true
            print("✅ 临时目录已清理 (尝试 \(attempt)/3)")
            break
          }
          Thread.sleep(forTimeInterval: 0.1 * Double(attempt))
        }
        if !cleanupSuccess {
          print("⚠️ 警告：临时目录清理失败: \(tempDir.path)")
          DispatchQueue.global(qos: .background).async {
            Thread.sleep(forTimeInterval: 1.0)
            try? fileManager.removeItem(at: tempDir)
          }
        }
      }
    }

    // 解压 EPUB
    do {
      try fileManager.unzipItem(at: sourceURL, to: tempDir)
    } catch {
      throw NSError(
        domain: "EpubProcessor", code: 100,
        userInfo: [NSLocalizedDescriptionKey: "EPUB 解压失败: \(error.localizedDescription)"])
    }

    let opfPath = try findOPFPath(in: tempDir)
    var opfContent = try String(contentsOf: opfPath, encoding: .utf8)

    // 更新标题
    if let newTitle = title {
      opfContent = updateTag(content: opfContent, tag: "dc:title", value: newTitle)
    }

    // 更新作者
    if let newAuthor = author {
      opfContent = updateTag(content: opfContent, tag: "dc:creator", value: newAuthor)
    }
    
    // 更新出版社 (修复：不存在则插入)
    if let newPublisher = publisher {
      opfContent = updateTag(content: opfContent, tag: "dc:publisher", value: newPublisher)
    }
    
    // 更新语言 (修复：不存在则插入)
    if let newLanguage = language {
      opfContent = updateTag(content: opfContent, tag: "dc:language", value: newLanguage)
    }
    
    // 更新ID (修复：不存在则插入)
    if let newIdentifier = identifier {
      opfContent = updateTag(content: opfContent, tag: "dc:identifier", value: newIdentifier)
    }
    
    // 更新简介 (修复：不存在则插入)
    if let newDescription = description {
      opfContent = updateTag(content: opfContent, tag: "dc:description", value: newDescription)
    }

    // 替换封面 (MARK: - 修改：添加新图片并更新 OPF)
    if let newCoverPath = coverPath {
      opfContent = try addNewCoverImage(in: tempDir, opfContent: opfContent, newCoverPath: newCoverPath)
    }

    // 保存修改后的 OPF 文件
    try opfContent.write(to: opfPath, atomically: true, encoding: .utf8)

    // ⭐ 关键：使用符合 EPUB 规范的方式重新打包
    let tempOutputEPUB = fileManager.temporaryDirectory.appendingPathComponent(
      UUID().uuidString + ".epub")

    do {
      try createCompliantEPUB(from: tempDir, to: tempOutputEPUB)

      // 打印文件大小对比
      if let originalSize = try? fileManager.attributesOfItem(atPath: sourceURL.path)[.size]
        as? Int64,
        let newSize = try? fileManager.attributesOfItem(atPath: tempOutputEPUB.path)[.size]
          as? Int64
      {
        let ratio = Double(newSize) / Double(originalSize) * 100
        print("📊 原始大小: \(formatBytes(originalSize))")
        print("📊 新文件大小: \(formatBytes(newSize)) (\(String(format: "%.1f", ratio))%)")
      }
    } catch {
      throw NSError(
        domain: "EpubProcessor", code: 101,
        userInfo: [NSLocalizedDescriptionKey: "EPUB 打包失败: \(error.localizedDescription)"])
    }

    // 确定最终输出位置
    let finalDestination = outputPath != nil ? URL(fileURLWithPath: outputPath!) : sourceURL
    var backupURL: URL?

    // 处理现有文件
    if fileManager.fileExists(atPath: finalDestination.path) {
      if overwrite || outputPath == nil {
        let backupName =
          finalDestination.deletingPathExtension().lastPathComponent
          + "_backup_\(UUID().uuidString).epub"
        backupURL = fileManager.temporaryDirectory.appendingPathComponent(backupName)

        do {
          try fileManager.copyItem(at: finalDestination, to: backupURL!)
          print("📦 已创建备份: \(backupURL!.lastPathComponent)")
        } catch {
          throw NSError(
            domain: "EpubProcessor", code: 102,
            userInfo: [NSLocalizedDescriptionKey: "创建备份失败: \(error.localizedDescription)"])
        }
      } else {
        throw NSError(
          domain: "EpubProcessor", code: 2, userInfo: [NSLocalizedDescriptionKey: "目标文件已存在"])
      }
    }

    // 移动到最终位置
    do {
      if fileManager.fileExists(atPath: finalDestination.path) {
        try fileManager.removeItem(at: finalDestination)
      }
      try fileManager.moveItem(at: tempOutputEPUB, to: finalDestination)

      if let backup = backupURL {
        try? fileManager.removeItem(at: backup)
        print("✅ 备份已删除")
      }

      print("✅ EPUB 处理完成: \(finalDestination.lastPathComponent)")
    } catch {
      // 恢复备份
      if let backup = backupURL {
        print("⚠️ 处理失败，正在恢复备份...")
        try? fileManager.removeItem(at: finalDestination)

        do {
          try fileManager.moveItem(at: backup, to: finalDestination)
          print("✅ 已从备份恢复原文件")
        } catch {
          throw NSError(
            domain: "EpubProcessor", code: 103,
            userInfo: [NSLocalizedDescriptionKey: "无法恢复备份，备份位于: \(backup.path)"])
        }
      }

      try? fileManager.removeItem(at: tempOutputEPUB)
      throw NSError(
        domain: "EpubProcessor", code: 104,
        userInfo: [NSLocalizedDescriptionKey: "文件替换失败: \(error.localizedDescription)"])
    }

    cleanupSuccess = true
    try? fileManager.removeItem(at: tempDir)
  }

  // MARK: - EPUB Compliant Packaging

  /// 创建符合 EPUB 规范的 ZIP 文件
  /// - mimetype 必须是第一个条目，无压缩
  /// - 其他文件使用 DEFLATE 压缩
  private func createCompliantEPUB(from sourceDir: URL, to destination: URL) throws {
    let fileManager = FileManager.default

    // 创建新的 archive
    let archive: Archive
    do {
      archive = try Archive(url: destination, accessMode: .create)
    } catch {
      throw NSError(
        domain: "EpubProcessor", code: 101,
        userInfo: [NSLocalizedDescriptionKey: "无法创建 ZIP archive: \(error.localizedDescription)"])
    }

    // 收集所有文件
    var allFiles: [URL] = []
    if let enumerator = fileManager.enumerator(
      at: sourceDir,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) {
      for case let fileURL as URL in enumerator {
        if let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]),
          resourceValues.isRegularFile == true
        {
          allFiles.append(fileURL)
        }
      }
    }

    // 步骤 1: 优先添加 mimetype 文件（无压缩）
    if let mimetypeFile = allFiles.first(where: { $0.lastPathComponent == "mimetype" }) {
      let relativePath = mimetypeFile.path.replacingOccurrences(of: sourceDir.path + "/", with: "")

      do {
        try archive.addEntry(
          with: relativePath,
          relativeTo: sourceDir,
          compressionMethod: .none  // ⭐ 关键：mimetype 无压缩
        )
        print("✅ mimetype 已添加（无压缩）")
      } catch {
        throw NSError(
          domain: "EpubProcessor", code: 106,
          userInfo: [NSLocalizedDescriptionKey: "添加 mimetype 失败: \(error.localizedDescription)"])
      }
    }

    // 步骤 2: 添加其他所有文件（使用 DEFLATE 压缩）
    for fileURL in allFiles {
      // 跳过已添加的 mimetype
      if fileURL.lastPathComponent == "mimetype" { continue }

      let relativePath = fileURL.path.replacingOccurrences(of: sourceDir.path + "/", with: "")

      do {
        try archive.addEntry(
          with: relativePath,
          relativeTo: sourceDir,
          compressionMethod: .deflate  // ⭐ 关键：使用 DEFLATE 压缩
        )
      } catch {
        throw NSError(
          domain: "EpubProcessor", code: 107,
          userInfo: [
            NSLocalizedDescriptionKey: "添加文件失败 (\(relativePath)): \(error.localizedDescription)"
          ])
      }
    }

    print("✅ EPUB 打包完成（符合规范）")
  }

  // MARK: - Helper Methods

  private func findOPFPath(in directory: URL) throws -> URL {
    if let enumerator = FileManager.default.enumerator(
      at: directory, includingPropertiesForKeys: nil)
    {
      while let fileURL = enumerator.nextObject() as? URL {
        if fileURL.pathExtension.lowercased() == "opf" {
          return fileURL
        }
      }
    }
    throw NSError(
      domain: "EpubProcessor", code: 3, userInfo: [NSLocalizedDescriptionKey: "无法找到 OPF 文件"])
  }

  private func updateTag(content: String, tag: String, value: String) -> String {
    // 1. 尝试匹配并替换现有标签
    let pattern = "<\(tag)(.*?)>(.*?)</\(tag)>"
    let regex = try? NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
    let newValue = "<\(tag)$1>\(value)</\(tag)>"
    let range = NSRange(location: 0, length: content.utf16.count)

    if let regex = regex, regex.firstMatch(in: content, options: [], range: range) != nil {
      // 存在则替换
      return regex.stringByReplacingMatches(
        in: content, options: [], range: range, withTemplate: newValue)
    } else {
      // 2. 不存在则插入
      // 寻找 metadata 的结束标签，它可以是 </metadata>, </opf:metadata> 等
      // 使用正则匹配 </...metadata>
      if let metadataEndRange = content.range(of: "</[^>]*metadata>", options: .regularExpression) {
        let newElement = "\n        <\(tag)>\(value)</\(tag)>"
        var newContent = content
        newContent.insert(contentsOf: newElement, at: metadataEndRange.lowerBound)
        return newContent
      }
    }
    
    // 如果连 metadata 结束标签都找不到，直接返回原内容（不太可能发生）
    return content
  }

  // MARK: - 核心修改：修复文件路径问题，确保新图片在正确的子文件夹中
  private func addNewCoverImage(in rootDir: URL, opfContent: String, newCoverPath: String) throws -> String {
    var coverId: String?

    // 1. 查找现有封面的 ID
    if let range = opfContent.range(of: "properties=\"[^\"]*cover-image[^\"]*\"", options: .regularExpression),
       let itemStart = opfContent.range(of: "<item", options: .backwards, range: opfContent.startIndex..<range.lowerBound),
       let itemEnd = opfContent.range(of: "/>", range: range.upperBound..<opfContent.endIndex) ?? opfContent.range(of: "</item>", range: range.upperBound..<opfContent.endIndex)
    {
        let itemTag = String(opfContent[itemStart.lowerBound..<itemEnd.upperBound])
        if let idRange = itemTag.range(of: "id=\"([^\"]+)\"", options: .regularExpression) {
            let idPart = String(itemTag[idRange])
            coverId = idPart.replacingOccurrences(of: "id=\"", with: "").replacingOccurrences(of: "\"", with: "")
        }
    }

    if coverId == nil {
      let metaPattern = "<meta[^>]+name=\"cover\"[^>]+content=\"([^\"]+)\""
      if let metaRegex = try? NSRegularExpression(pattern: metaPattern),
        let metaMatch = metaRegex.firstMatch(in: opfContent, range: NSRange(location: 0, length: opfContent.utf16.count)),
        let rangeContent = Range(metaMatch.range(at: 1), in: opfContent)
      {
        coverId = String(opfContent[rangeContent])
      }
    }

    guard let validId = coverId else {
      print("⚠️ 无法在 OPF 中找到封面记录 ID，跳过替换")
      return opfContent
    }

    var newOpfContent = opfContent
    
    // 2. 找到对应的 item 标签，并提取原始 href (以便知道图片所在的文件夹)
    let itemPattern = "(<item[^>]*id=\"\(validId)\"[^>]*>)"
    if let regex = try? NSRegularExpression(pattern: itemPattern),
       let match = regex.firstMatch(in: opfContent, range: NSRange(location: 0, length: opfContent.utf16.count)),
       let matchRange = Range(match.range, in: opfContent) {
        
        var currentItemTag = String(opfContent[matchRange])
        
        // 2.1 提取旧文件的信息
        var oldHref = ""
        var oldMediaType = "image/jpeg"
        
        if let hrefRange = currentItemTag.range(of: "href=\"([^\"]+)\"", options: .regularExpression) {
            let part = String(currentItemTag[hrefRange])
            oldHref = part.replacingOccurrences(of: "href=\"", with: "").replacingOccurrences(of: "\"", with: "")
        }
        
        if let typeRange = currentItemTag.range(of: "media-type=\"([^\"]+)\"", options: .regularExpression) {
            let part = String(currentItemTag[typeRange])
            oldMediaType = part.replacingOccurrences(of: "media-type=\"", with: "").replacingOccurrences(of: "\"", with: "")
        }
        
        // 3. 准备文件路径操作
        let opfURL = try findOPFPath(in: rootDir)
        let opfDir = opfURL.deletingLastPathComponent()
        
        // 3.1 提取旧封面的目录部分 (例如 "Images")
        // 如果 oldHref 是 "Images/cover.jpg"，dirPart 就是 "Images"
        // 如果 oldHref 是 "cover.jpg"，dirPart 就是 ""
        let oldHrefPath = oldHref as NSString
        let relativeDirectory = oldHrefPath.deletingLastPathComponent
        
        // 3.2 准备新文件名和 MIME
        let newExt = (newCoverPath as NSString).pathExtension.lowercased()
        let newMimeType: String
        switch newExt {
        case "png": newMimeType = "image/png"
        case "jpg", "jpeg": newMimeType = "image/jpeg"
        case "gif": newMimeType = "image/gif"
        case "webp": newMimeType = "image/webp"
        default: newMimeType = "image/jpeg"
        }
        
        let newFileNameOnly = "cover_\(UUID().uuidString.prefix(8)).\(newExt)"
        
        // 3.3 构造 OPF 中使用的新 href (例如 "Images/cover_uuid.png")
        let newRelativeHref: String
        if relativeDirectory.isEmpty {
            newRelativeHref = newFileNameOnly
        } else {
            newRelativeHref = "\(relativeDirectory)/\(newFileNameOnly)"
        }
        
        // 3.4 构造物理文件复制的目标路径
        let destinationURL = opfDir.appendingPathComponent(newRelativeHref)
        
        // 4. 复制新文件
        do {
            try FileManager.default.copyItem(atPath: newCoverPath, toPath: destinationURL.path)
            print("✅ 新封面已添加至: \(newRelativeHref)")
        } catch {
            throw NSError(
                domain: "EpubProcessor", code: 105,
                userInfo: [NSLocalizedDescriptionKey: "复制新封面失败: \(error.localizedDescription)"])
        }
        
        // 5. 修改 OPF 内容
        
        // 5.1 更新 href
        let hrefPattern = "href=\"[^\"]+\""
        if let hrefRegex = try? NSRegularExpression(pattern: hrefPattern) {
             let range = NSRange(location: 0, length: currentItemTag.utf16.count)
             currentItemTag = hrefRegex.stringByReplacingMatches(in: currentItemTag, options: [], range: range, withTemplate: "href=\"\(newRelativeHref)\"")
        }
        
        // 5.2 更新 media-type
        let mimePattern = "media-type=\"[^\"]+\""
        if let mimeRegex = try? NSRegularExpression(pattern: mimePattern) {
            let range = NSRange(location: 0, length: currentItemTag.utf16.count)
            currentItemTag = mimeRegex.stringByReplacingMatches(in: currentItemTag, options: [], range: range, withTemplate: "media-type=\"\(newMimeType)\"")
        }
        
        // 5.3 构建“保留条目”
        let legacyId = "legacy_cover_\(UUID().uuidString.prefix(6))"
        let legacyItemEntry = "\n        <item id=\"\(legacyId)\" href=\"\(oldHref)\" media-type=\"\(oldMediaType)\" />"
        
        // 5.4 执行替换
        let combinedEntry = currentItemTag + legacyItemEntry
        newOpfContent.replaceSubrange(matchRange, with: combinedEntry)
        
        print("✅ OPF 已更新: ID=\(validId) 指向 \(newRelativeHref)，保留旧文件引用")
    }
    
    return newOpfContent
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let kb = Double(bytes) / 1024
    let mb = kb / 1024

    if mb >= 1 {
      return String(format: "%.2f MB", mb)
    } else {
      return String(format: "%.2f KB", kb)
    }
  }
}
