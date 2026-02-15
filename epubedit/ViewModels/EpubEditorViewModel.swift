//
//  EpubEditorViewModel.swift
//  epubedit
//

internal import Combine
import Foundation
import SwiftUI
import AppKit // 新增：引入 AppKit 以使用 NSOpenPanel

@MainActor
class EpubEditorViewModel: ObservableObject {
  @Published var files: [EpubFile] = []

  // MARK: - UI State
  // 新增：将文件选择器的显示状态移至 VM，以便通过菜单栏 Cmd+O 控制
  @Published var showingFilePicker = false

  // MARK: - Processing State
  @Published var isProcessing = false
  @Published var overwriteOriginal = true
  @Published var processingProgress: Double = 0
  @Published var currentProcessingFile: String?
  @Published var processedFiles: [UUID: ProcessingStatus] = [:]
  @Published var lastError: String?

  // MARK: - Import State
  @Published var isImporting = false

  // MARK: - Helper
  var hasAnyChanges: Bool {
    return files.contains { $0.hasChanges }
  }

  var changedFilesCount: Int {
    return files.filter { $0.hasChanges }.count
  }

  private let resourceManager = SecurityScopedResourceManager()

  // 修复：isImporting 期间调用 addFiles 不再丢弃，而是排队等待
  private var pendingImportURLs: [URL] = []

  func addFiles(_ urls: [URL]) {
    // 正在导入时，新文件进入等待队列，不丢弃
    guard !isImporting else {
      print("⏳ 导入中，\(urls.count) 个文件加入队列")
      pendingImportURLs.append(contentsOf: urls)
      return
    }
    isImporting = true

    Task {
      try? await Task.sleep(nanoseconds: 10_000_000)

      for url in urls {
        if files.contains(where: { $0.url == url }) { continue }

        let accessGranted = url.startAccessingSecurityScopedResource()

        let metadata = await Task.detached(priority: .userInitiated) {
          return await EpubMetadataExtractor.extract(from: url, hasAccess: accessGranted)
        }.value

        var newFile = EpubFile(url: url)

        if let metadata = metadata {
          newFile.originalTitle = metadata.title
          newFile.originalAuthor = metadata.author
          newFile.originalPublisher = metadata.publisher
          newFile.originalLanguage = metadata.language
          newFile.originalIdentifier = metadata.identifier
          newFile.originalDescription = metadata.description
          newFile.originalCoverData = metadata.coverData
          newFile.originalCoverExtension = metadata.coverExtension // 新增：保存原始封面后缀
          
          newFile.editedTitle = metadata.title ?? ""
          newFile.editedAuthor = metadata.author ?? ""
          newFile.editedPublisher = metadata.publisher ?? ""
          newFile.editedLanguage = metadata.language ?? ""
          newFile.editedIdentifier = metadata.identifier ?? ""
          newFile.editedDescription = metadata.description ?? ""
        } else {
            // 默认使用文件名作为标题（需要解码）
            let rawFilename = url.lastPathComponent
            let decodedFilename = rawFilename.removingPercentEncoding ?? rawFilename
            let title = (decodedFilename as NSString).deletingPathExtension
            newFile.editedTitle = title
        }

        files.append(newFile)

        if accessGranted {
          resourceManager.add(id: newFile.id, url: url)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
      }

      isImporting = false

      // 本批结束后，消费队列中等待的文件
      if !pendingImportURLs.isEmpty {
        let next = pendingImportURLs
        pendingImportURLs.removeAll()
        print("📬 消费队列: \(next.count) 个文件")
        addFiles(next)
      }
    }
  }

  func removeFile(_ id: UUID) {
    resourceManager.remove(id: id)

    if let index = files.firstIndex(where: { $0.id == id }) {
      files[index].cleanup()
    }

    files.removeAll { $0.id == id }
    processedFiles.removeValue(forKey: id)
  }
  
  // 新增：清空所有文件
  func removeAllFiles() {
    // 1. 清理所有文件的临时资源
    for index in files.indices {
      files[index].cleanup()
    }
    
    // 2. 清空数组和状态
    files.removeAll()
    processedFiles.removeAll()
    
    // 3. 清理权限资源
    resourceManager.cleanup()
    
    currentProcessingFile = nil
    lastError = nil
    
    print("✅ 已清空列表")
  }

  func resetAllFiles() {
    let resetCount = changedFilesCount
    for index in files.indices where files[index].hasChanges {
      files[index].reset()
    }
    print("✅ 已重置 \(resetCount) 个文件的修改")
  }

  // MARK: - Single File Operations (Context Menu)

  /// 单个文件：重置修改
  func resetFile(for id: UUID) {
    if let index = files.firstIndex(where: { $0.id == id }) {
      files[index].reset()
      print("✅ 已重置单个文件: \(files[index].displayName)")
    }
  }

  /// 单个文件：从文件名解析信息
  func updateMetadataFromFilename(for id: UUID) {
    guard let index = files.firstIndex(where: { $0.id == id }) else { return }
    
    let url = files[index].url
    
    // 1. 获取纯净的文件名 (解码 URL -> 转字符串 -> 去后缀)
    let rawLastPathComponent = url.lastPathComponent
    let decodedName = rawLastPathComponent.removingPercentEncoding ?? rawLastPathComponent
    let filename = (decodedName as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
    
    // 2. 分割逻辑
    let components = filename.split(separator: "-")
    
    var newTitle = ""
    var newAuthor = ""
    
    if components.count > 1 {
      // 最后一个部分作为作者
      newAuthor = String(components.last!).trimmingCharacters(in: .whitespaces)
      // 前面所有部分组合作为书名
      newTitle = components.dropLast().joined(separator: "-").trimmingCharacters(in: .whitespaces)
    } else {
      // 如果没有分隔符，整个文件名作为书名
      newTitle = filename
    }
    
    // 3. 更新模型
    if !newTitle.isEmpty {
      files[index].editedTitle = newTitle
    }
    
    // 仅当解析出作者时才更新，避免清空已有作者
    if !newAuthor.isEmpty {
      files[index].editedAuthor = newAuthor
    }
    
    print("✅ 单个更新信息: \(newTitle) / \(newAuthor)")
  }

  /// 单个文件：重命名
  func renameFile(for id: UUID) {
    guard let index = files.firstIndex(where: { $0.id == id }) else { return }
    
    let file = files[index]
    let fm = FileManager.default
    
    // 获取当前编辑的书名和作者
    let title = file.editedTitle.trimmingCharacters(in: .whitespaces)
    let author = file.editedAuthor.trimmingCharacters(in: .whitespaces)
    
    let safeTitle = sanitizeFilename(title.isEmpty ? "无标题" : title)
    let safeAuthor = sanitizeFilename(author)
    
    // 构造新文件名
    var newFilename = safeTitle
    if !safeAuthor.isEmpty {
      newFilename += "-\(safeAuthor)"
    }
    newFilename += ".epub"
    
    let currentURL = file.url
    let directory = currentURL.deletingLastPathComponent()
    var destinationURL = directory.appendingPathComponent(newFilename)
    
    // 检查文件名冲突
    var counter = 1
    while fm.fileExists(atPath: destinationURL.path) && destinationURL.path != currentURL.path {
      let nameWithoutExt = (newFilename as NSString).deletingPathExtension
      let ext = (newFilename as NSString).pathExtension
      let tempName = "\(nameWithoutExt)_\(counter).\(ext)"
      destinationURL = directory.appendingPathComponent(tempName)
      counter += 1
    }
    
    if destinationURL.path == currentURL.path {
        print("⚠️ 文件名未改变，跳过重命名")
        return
    }
    
    // 定义核心重命名操作
    func performRename() throws {
      try fm.moveItem(at: currentURL, to: destinationURL)
      // 成功后更新 UI
      self.files[index].url = destinationURL
      if self.resourceManager.hasResource(id: file.id) {
          self.resourceManager.add(id: file.id, url: destinationURL)
      }
      print("✅ 重命名成功: \(destinationURL.lastPathComponent)")
    }
    
    // 尝试重命名
    do {
      try performRename()
    } catch {
      let nsError = error as NSError
      // 捕获 Cocoa 错误 513: "You don’t have permission"
      if nsError.domain == NSCocoaErrorDomain && nsError.code == 513 {
        print("⚠️ 权限不足，尝试请求文件夹权限...")
        
        // 尝试请求父文件夹权限
        if requestFolderAccess(for: directory) {
          // 如果用户授权成功，重试
          do {
             try performRename()
          } catch {
             lastError = "即使授权后重命名仍失败: \(error.localizedDescription)"
          }
        } else {
          lastError = "未获得文件夹权限，无法重命名。"
        }
      } else {
        // 其他错误直接显示
        print("❌ 重命名失败: \(error.localizedDescription)")
        lastError = "无法重命名文件：\(error.localizedDescription)"
      }
    }
  }
  
  // MARK: - Permission Helper
  
  /// 弹出 NSOpenPanel 请求文件夹权限
  private func requestFolderAccess(for folderURL: URL) -> Bool {
    let openPanel = NSOpenPanel()
    openPanel.message = "App 需要访问该文件夹以修改文件名"
    openPanel.prompt = "授权访问"
    openPanel.canChooseFiles = false
    openPanel.canChooseDirectories = true
    openPanel.allowsMultipleSelection = false
    openPanel.directoryURL = folderURL
    
    let result = openPanel.runModal()
    
    if result == .OK, let url = openPanel.url {
      // 这里的关键是 startAccessing，它会告诉系统用户刚刚授权了这个目录
      return url.startAccessingSecurityScopedResource()
    }
    return false
  }

  private func sanitizeFilename(_ name: String) -> String {
    // 替换文件名中的非法字符
    return name.replacingOccurrences(of: "/", with: "_")
               .replacingOccurrences(of: ":", with: "_")
               .replacingOccurrences(of: "\\", with: "_")
  }

  func processAllFiles() async {
    isProcessing = true
    processingProgress = 0
    processedFiles.removeAll()
    lastError = nil

    try? await Task.sleep(nanoseconds: 10_000_000)

    let totalFiles = files.count
    var hasError = false
    var errorMessages: [String] = []

    for (index, file) in files.enumerated() {
      guard file.hasChanges else {
        processedFiles[file.id] = .success
        processingProgress = Double(index + 1) / Double(totalFiles)
        continue
      }

      currentProcessingFile = file.displayName

      if let fileIndex = files.firstIndex(where: { $0.id == file.id }) {
        files[fileIndex].processingStatus = .processing
      }

      do {
        try await processFile(file)

        if let fileIndex = files.firstIndex(where: { $0.id == file.id }) {
          files[fileIndex].processingStatus = .success
          files[fileIndex].commitChanges()
        }
        processedFiles[file.id] = .success

      } catch {
        hasError = true
        let errorMsg = "文件: \(file.displayName)\n错误: \(error.localizedDescription)"
        errorMessages.append(errorMsg)

        if let fileIndex = files.firstIndex(where: { $0.id == file.id }) {
          files[fileIndex].processingStatus = .failed
          files[fileIndex].errorMessage = error.localizedDescription
        }
        processedFiles[file.id] = .failed
      }

      processingProgress = Double(index + 1) / Double(totalFiles)
      try? await Task.sleep(nanoseconds: 50_000_000)
    }

    currentProcessingFile = nil
    isProcessing = false

    if hasError {
      lastError = errorMessages.joined(separator: "\n\n")
    }
  }

  // MARK: - Single File Processing
  // 新增：处理单个文件的逻辑
  func processSingleFile(for id: UUID) async {
    // 找到文件
    guard let index = files.firstIndex(where: { $0.id == id }) else { return }
    let file = files[index]
    
    // 如果没有修改，也可以选择不执行，或者强制执行。此处为了用户体验，若无修改可跳过
    // 但用户显式点击执行，通常期望发生动作。这里我们检查下
    if !file.hasChanges {
       // 如果需要提示用户 "无修改"，可以在 UI 层判断，这里暂不阻断或直接返回
       print("⚠️ 文件无修改，跳过: \(file.displayName)")
       return
    }
    
    isProcessing = true
    currentProcessingFile = file.displayName
    
    // 更新该文件的状态为处理中
    files[index].processingStatus = .processing
    
    do {
      try await processFile(file)
      
      // 成功后更新状态
      if let idx = files.firstIndex(where: { $0.id == id }) {
        files[idx].processingStatus = .success
        files[idx].commitChanges()
        processedFiles[id] = .success
      }
    } catch {
      // 失败处理
      if let idx = files.firstIndex(where: { $0.id == id }) {
        files[idx].processingStatus = .failed
        files[idx].errorMessage = error.localizedDescription
        processedFiles[id] = .failed
        lastError = error.localizedDescription // 更新最后一次错误供 UI 显示
      }
    }
    
    currentProcessingFile = nil
    isProcessing = false
  }

  private func processFile(_ file: EpubFile) async throws {
    let sourcePath = file.url.path
    let overwrite = overwriteOriginal
    let title = file.editedTitle.isEmpty ? nil : file.editedTitle
    let author = file.editedAuthor.isEmpty ? nil : file.editedAuthor
    
    let publisher = file.editedPublisher.isEmpty ? nil : file.editedPublisher
    let language = file.editedLanguage.isEmpty ? nil : file.editedLanguage
    let identifier = file.editedIdentifier.isEmpty ? nil : file.editedIdentifier
    let description = file.editedDescription.isEmpty ? nil : file.editedDescription
    
    let coverPath = file.editedCoverURL?.path

    if title == nil && author == nil && publisher == nil && language == nil && identifier == nil && description == nil && coverPath == nil {
      throw NSError(
        domain: "EpubEditor", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "无修改"])
    }

    let needsAccess = resourceManager.hasResource(id: file.id)
    let url = file.url

    let isAccessing: Bool
    if needsAccess {
      isAccessing = url.startAccessingSecurityScopedResource()
    } else {
      isAccessing = false
    }

    defer {
      if isAccessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    if !FileManager.default.fileExists(atPath: sourcePath) {
      throw NSError(
        domain: "EpubEditor", code: 404,
        userInfo: [NSLocalizedDescriptionKey: "文件未找到，可能已被移动或删除"])
    }

    try await Task.detached(priority: .userInitiated) {
      let processor = await EpubProcessor(
        sourcePath: sourcePath,
        outputPath: nil,
        overwrite: overwrite
      )
      try await processor.run(
          title: title,
          author: author,
          publisher: publisher,
          language: language,
          identifier: identifier,
          description: description,
          coverPath: coverPath
      )
    }.value
  }

  deinit {
    resourceManager.cleanup()
  }
}

// MARK: - Security-Scoped Resource Manager

final class SecurityScopedResourceManager: @unchecked Sendable {
  private var resources: [UUID: URL] = [:]
  private let queue = DispatchQueue(label: "com.epubedit.resources", qos: .userInitiated)

  func add(id: UUID, url: URL) {
    queue.sync { resources[id] = url }
  }

  func remove(id: UUID) {
    queue.sync {
      if let url = resources[id] {
        url.stopAccessingSecurityScopedResource()
        resources.removeValue(forKey: id)
      }
    }
  }

  func hasResource(id: UUID) -> Bool {
    queue.sync { resources[id] != nil }
  }

  func cleanup() {
    queue.sync {
      for (_, url) in resources {
        url.stopAccessingSecurityScopedResource()
      }
      resources.removeAll()
    }
  }
}
