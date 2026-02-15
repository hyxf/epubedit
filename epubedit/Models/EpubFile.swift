//
//  EpubFile.swift
//  epubedit
//

import Foundation
import SwiftUI

struct EpubFile: Identifiable {
  let id = UUID()
  // 修改：将 let 改为 var，允许重命名后更新路径
  var url: URL

  // 原始元数据（用于比对修改）
  var originalTitle: String?
  var originalAuthor: String?
  var originalPublisher: String?
  var originalLanguage: String?
  var originalIdentifier: String?
  var originalDescription: String?
  var originalCoverData: Data?
  var originalCoverExtension: String? // 新增：保存原始封面的拓展名

  // 编辑中的元数据（带状态自动重置功能）
  var editedTitle: String = "" {
    didSet {
      // 当内容发生变化且当前已处理过（成功或失败），重置为待处理状态
      if oldValue != editedTitle {
        resetStatusIfNeeded()
      }
    }
  }

  var editedAuthor: String = "" {
    didSet {
      if oldValue != editedAuthor {
        resetStatusIfNeeded()
      }
    }
  }
  
  var editedPublisher: String = "" {
    didSet {
      if oldValue != editedPublisher {
        resetStatusIfNeeded()
      }
    }
  }
  
  var editedLanguage: String = "" {
    didSet {
      if oldValue != editedLanguage {
        resetStatusIfNeeded()
      }
    }
  }
  
  var editedIdentifier: String = "" {
    didSet {
      if oldValue != editedIdentifier {
        resetStatusIfNeeded()
      }
    }
  }
  
  var editedDescription: String = "" {
    didSet {
      if oldValue != editedDescription {
        resetStatusIfNeeded()
      }
    }
  }

  // 封面修改专用
  var editedCoverURL: URL? {
    didSet {
      // 清理旧的临时文件
      if let oldURL = oldValue, oldURL != editedCoverURL {
        cleanupTempCover(oldURL)
      }

      // 当设置了新封面（非空）且与旧值不同时，重置状态
      if editedCoverURL != nil, oldValue != editedCoverURL {
        resetStatusIfNeeded()
      }
    }
  }

  var editedCoverData: Data?

  // 处理状态
  var processingStatus: ProcessingStatus = .pending
  var errorMessage: String?

  var displayName: String {
    url.lastPathComponent
  }

  var fileSize: String {
    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
      let size = attrs[.size] as? Int64
    {
      return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    return "未知"
  }

  // 计算属性：判断是否有未保存的更改
  var hasChanges: Bool {
    let titleChanged = !editedTitle.isEmpty && editedTitle != (originalTitle ?? "")
    let authorChanged = !editedAuthor.isEmpty && editedAuthor != (originalAuthor ?? "")
    let publisherChanged = editedPublisher != (originalPublisher ?? "")
    let languageChanged = editedLanguage != (originalLanguage ?? "")
    let identifierChanged = editedIdentifier != (originalIdentifier ?? "")
    let descriptionChanged = editedDescription != (originalDescription ?? "")
    let coverChanged = editedCoverURL != nil
    
    return titleChanged || authorChanged || publisherChanged || languageChanged || identifierChanged || descriptionChanged || coverChanged
  }

  // MARK: - Helper Methods

  /// 当用户修改了已完成项目的内容时，重置状态图标
  private mutating func resetStatusIfNeeded() {
    if processingStatus == .success || processingStatus == .failed {
      processingStatus = .pending
      errorMessage = nil
    }
  }

  /// 清理临时封面文件
  private func cleanupTempCover(_ url: URL) {
    // 只清理临时目录中的文件，避免误删用户文件
    let tempDir = FileManager.default.temporaryDirectory
    if url.path.hasPrefix(tempDir.path) {
      try? FileManager.default.removeItem(at: url)
      print("🗑️ 已清理临时封面: \(url.lastPathComponent)")
    }
  }

  /// 提交更改：将编辑后的值同步为原始值
  mutating func commitChanges() {
    if !editedTitle.isEmpty {
      originalTitle = editedTitle
    }

    if !editedAuthor.isEmpty {
      originalAuthor = editedAuthor
    }
    
    originalPublisher = editedPublisher
    originalLanguage = editedLanguage
    originalIdentifier = editedIdentifier
    originalDescription = editedDescription

    if let newCoverData = editedCoverData {
      originalCoverData = newCoverData
      // 如果提交了新封面，更新 originalExtension
      if let url = editedCoverURL {
          originalCoverExtension = url.pathExtension
      }
    } else if let url = editedCoverURL, let data = try? Data(contentsOf: url) {
      originalCoverData = data
      originalCoverExtension = url.pathExtension
    }

    // 清理临时封面
    if let tempURL = editedCoverURL {
      cleanupTempCover(tempURL)
    }

    editedCoverURL = nil
    editedCoverData = nil
  }

  /// 清理所有临时资源（在文件被移除时调用）
  mutating func cleanup() {
    if let tempURL = editedCoverURL {
      cleanupTempCover(tempURL)
    }
    editedCoverURL = nil
    editedCoverData = nil
  }

  /// 重置所有修改（方案 B：批量重置）
  mutating func reset() {
    // 1. 恢复原始值
    editedTitle = originalTitle ?? ""
    editedAuthor = originalAuthor ?? ""
    editedPublisher = originalPublisher ?? ""
    editedLanguage = originalLanguage ?? ""
    editedIdentifier = originalIdentifier ?? ""
    editedDescription = originalDescription ?? ""

    // 2. 清理临时封面
    if let tempURL = editedCoverURL {
      cleanupTempCover(tempURL)
    }
    editedCoverURL = nil
    editedCoverData = nil

    // 3. 重置处理状态
    processingStatus = .pending
    errorMessage = nil

    print("🔄 已重置文件: \(displayName)")
  }
}

enum ProcessingStatus: Equatable {
  case pending
  case processing
  case success
  case failed

  var icon: String {
    switch self {
    case .pending: return "circle"
    case .processing: return "arrow.triangle.2.circlepath"
    case .success: return "checkmark.circle.fill"
    case .failed: return "xmark.circle.fill"
    }
  }

  var color: Color {
    switch self {
    case .pending: return .gray
    case .processing: return .blue
    case .success: return .green
    case .failed: return .red
    }
  }
}
