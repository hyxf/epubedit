//
//  FileDetailView.swift
//  epubedit
//

import SwiftUI
import UniformTypeIdentifiers

struct FileDetailView: View {
  @Binding var file: EpubFile
  @State private var showingImagePicker = false
  @State private var isDraggingImage = false
  @State private var isAdvancedMode = false
  
  // 计算当前应该使用的封面拓展名
  private var currentCoverExtension: String {
      // 1. 如果有编辑过的封面，使用该文件的后缀
      if let editedURL = file.editedCoverURL {
          return editedURL.pathExtension.lowercased()
      }
      // 2. 否则使用原始 EPUB 内的图片后缀
      if let originalExt = file.originalCoverExtension, !originalExt.isEmpty {
          return originalExt.lowercased()
      }
      // 3. 默认回退
      return "jpg"
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 25) {
        // 顶部区域：左侧封面，右侧基本信息
        HStack(alignment: .top, spacing: 25) {
          // 封面预览区（支持点击和拖拽）
          CoverPreviewCard(
            coverData: file.editedCoverData ?? file.originalCoverData,
            title: file.editedTitle.isEmpty ? (file.originalTitle ?? "无标题") : file.editedTitle,
            author: file.editedAuthor.isEmpty ? (file.originalAuthor ?? "") : file.editedAuthor,
            // MARK: - 核心改动：传入计算好的后缀
            fileExtension: currentCoverExtension,
            isDragging: isDraggingImage,
            onSelectCover: {
              showingImagePicker = true
            },
            onDropCover: { url in
              handleImageSelection(url)
            }
          )
          .onDrop(of: [.fileURL], isTargeted: $isDraggingImage) { providers in
            handleImageDrop(providers)
            return true
          }
          .frame(width: 220)  // 修改：设置固定宽度，避免封面区域留白过多

          // 元数据编辑区（预填充原始值）
          VStack(spacing: 25) {
            SimpleMetadataField(
              title: "书名",
              icon: "book.fill",
              value: $file.editedTitle,
              originalValue: file.originalTitle,
              placeholder: "请输入书名"
            )

            SimpleMetadataField(
              title: "作者",
              icon: "person.fill",
              value: $file.editedAuthor,
              originalValue: file.originalAuthor,
              placeholder: "请输入作者"
            )
            
            // 高级模式开关
            Toggle(isOn: $isAdvancedMode) {
                Text("高级模式")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .toggleStyle(.switch)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
          }
          .frame(maxWidth: .infinity)  // 修改：让右侧信息区域自动填充剩余空间
        }
        
        // 底部区域：高级选项（双列显示）
        if isAdvancedMode {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 25, alignment: .top),
                GridItem(.flexible(), spacing: 25, alignment: .top)
            ], spacing: 25) {
                
                SimpleMetadataField(
                  title: "出版社",
                  icon: "building.2.fill",
                  value: $file.editedPublisher,
                  originalValue: file.originalPublisher,
                  placeholder: "请输入出版社"
                )
                
                SimpleMetadataField(
                  title: "语言",
                  icon: "globe",
                  value: $file.editedLanguage,
                  originalValue: file.originalLanguage,
                  placeholder: "例如: zh-CN"
                )
                
                SimpleMetadataField(
                  title: "唯一ID",
                  icon: "key.fill",
                  value: $file.editedIdentifier,
                  originalValue: file.originalIdentifier,
                  placeholder: "ISBN 或 UUID"
                )
                
                MultiLineMetadataField(
                  title: "简介/描述",
                  icon: "text.alignleft",
                  value: $file.editedDescription,
                  originalValue: file.originalDescription,
                  placeholder: "请输入书籍简介"
                )
            }
        }

        Spacer(minLength: 20)
      }
      .padding(32)
    }
    .background(Color(nsColor: .textBackgroundColor))
    .fileImporter(
      isPresented: $showingImagePicker,
      allowedContentTypes: [.png, .jpeg],
      allowsMultipleSelection: false
    ) { result in
      switch result {
      case .success(let urls):
        if let url = urls.first {
          handleImageSelection(url)
        }
      case .failure(let error):
        print("❌ 图片选择错误: \(error)")
      }
    }
  }

  private func handleImageSelection(_ url: URL) {
    // 修复问题1 & 2：改进的临时文件管理
    let isSecurityScoped = url.startAccessingSecurityScopedResource()
    defer {
      if isSecurityScoped {
        url.stopAccessingSecurityScopedResource()
      }
    }

    do {
      // 1. 读取数据
      let data = try Data(contentsOf: url)

      // 2. 创建持久化的临时文件
      let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
        "epubedit-covers", isDirectory: true)

      // 确保目录存在
      try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

      let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
      let tempFilename = "cover_\(UUID().uuidString).\(ext)"
      let tempURL = tempDir.appendingPathComponent(tempFilename)

      // 3. 写入临时文件
      try data.write(to: tempURL)

      // 4. 更新模型（旧文件会在 didSet 中自动清理）
      file.editedCoverURL = tempURL
      file.editedCoverData = data
      print("✅ 封面已更新并缓存: \(tempURL.lastPathComponent)")

    } catch {
      print("❌ 无法读取或缓存图片: \(error.localizedDescription)")
    }
  }

  private func handleImageDrop(_ providers: [NSItemProvider]) {
    guard let provider = providers.first else { return }

    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
      if let error = error {
        print("❌ 拖拽图片错误: \(error)")
        return
      }

      if let data = item as? Data,
        let url = URL(dataRepresentation: data, relativeTo: nil)
      {
        let ext = url.pathExtension.lowercased()
        if ["jpg", "jpeg", "png"].contains(ext) {
          DispatchQueue.main.async {
            handleImageSelection(url)
          }
        } else {
          print("❌ 不支持的图片格式: \(ext)")
        }
      }
    }
  }
}

// MARK: - 封面预览卡片

struct CoverPreviewCard: View {
  let coverData: Data?
  let title: String
  let author: String
  let fileExtension: String // 新增：接收具体的文件后缀
  
  let isDragging: Bool
  let onSelectCover: () -> Void
  let onDropCover: (URL) -> Void

  var body: some View {
    VStack(spacing: 16) {
      Text("封面")
        .font(.headline)
        .frame(maxWidth: .infinity, alignment: .leading)

      Button(action: onSelectCover) {
        ZStack {
          if let data = coverData,
            let nsImage = NSImage(data: data)
          {
            Image(nsImage: nsImage)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: 120, height: 180)
              .clipShape(RoundedRectangle(cornerRadius: 12))
              .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
              .overlay {
                RoundedRectangle(cornerRadius: 12)
                  .strokeBorder(isDragging ? Color.blue : Color.clear, lineWidth: 3)
              }
          } else {
            RoundedRectangle(cornerRadius: 12)
              .fill(Color.blue.opacity(isDragging ? 0.1 : 0.05))
              .frame(width: 120, height: 180)
              .overlay {
                VStack(spacing: 12) {
                  Image(systemName: "photo.badge.plus")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)

                  Text("点击选择\n或拖拽图片")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                }
              }
              .overlay {
                RoundedRectangle(cornerRadius: 12)
                  .strokeBorder(
                    isDragging ? Color.blue : Color.gray.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: isDragging ? [] : [6, 3])
                  )
              }
          }

          if isDragging {
            RoundedRectangle(cornerRadius: 12)
              .fill(Color.blue.opacity(0.2))
              .frame(width: 120, height: 180)
              .overlay {
                VStack(spacing: 8) {
                  Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)

                  Text("松开替换")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.blue)
                }
              }
          }
        }
      }
      .buttonStyle(.plain)
      .animation(.spring(response: 0.3), value: isDragging)

      // MARK: - 修改：增加保存链接
      HStack(spacing: 8) {
        Text("支持多种图片格式")
          .font(.caption2)
          .foregroundStyle(.tertiary)
        
        if coverData != nil {
          Text("|")
            .font(.caption2)
            .foregroundStyle(.tertiary)
            
          Button("保存原图") {
            saveCoverToDisk()
          }
          .buttonStyle(.link)
          .controlSize(.mini)
          .font(.caption2)
        }
      }
    }
    .padding(24)
    .background {
      RoundedRectangle(cornerRadius: 16)
        .fill(.background)
        .shadow(color: .black.opacity(0.05), radius: 10, y: 2)
    }
  }
  
  // 新增：保存封面到本地的方法 (使用传递进来的准确后缀)
  private func saveCoverToDisk() {
    guard let data = coverData else { return }
    
    // 1. 处理文件名：清理空格和非法字符
    let safeTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                         .replacingOccurrences(of: "/", with: "_")
                         .replacingOccurrences(of: ":", with: "_")
                         .replacingOccurrences(of: "\\", with: "_")
    
    let safeAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
                           .replacingOccurrences(of: "/", with: "_")
                           .replacingOccurrences(of: ":", with: "_")
                           .replacingOccurrences(of: "\\", with: "_")
    
    // 2. 构造文件名: 书名-作者.扩展名
    var fileName = safeTitle.isEmpty ? "Cover" : safeTitle
    if !safeAuthor.isEmpty {
      fileName += "-\(safeAuthor)"
    }
    
    // 确保后缀不为空
    let ext = fileExtension.isEmpty ? "jpg" : fileExtension
    fileName += ".\(ext)"
    
    // 3. 配置保存面板
    let savePanel = NSSavePanel()
    // 允许所有图片类型 (public.image)，不再局限于特定数组
    savePanel.allowedContentTypes = [.image]
    savePanel.canCreateDirectories = true
    savePanel.nameFieldStringValue = fileName
    savePanel.title = "保存封面图片"
    
    savePanel.begin { response in
      if response == .OK, let url = savePanel.url {
        try? data.write(to: url)
      }
    }
  }
}

// MARK: - 简化的元数据输入框

struct SimpleMetadataField: View {
  let title: String
  let icon: String
  @Binding var value: String
  let originalValue: String? // 新增：用于比较
  let placeholder: String

  private var isModified: Bool {
    value != (originalValue ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: icon)
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(.primary)

      TextField(placeholder, text: $value)
        .textFieldStyle(.plain)
        .font(.body)
        .padding(12)
        .background {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
              isModified ? Color.blue : Color.gray.opacity(0.2),
              lineWidth: isModified ? 1.5 : 1
            )
        }
    }
    .padding(16)
    .background {
      RoundedRectangle(cornerRadius: 12)
        .fill(.background)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
  }
}

// MARK: - 多行元数据输入框 (用于简介)

struct MultiLineMetadataField: View {
  let title: String
  let icon: String
  @Binding var value: String
  let originalValue: String? // 新增：用于比较
  let placeholder: String

  private var isModified: Bool {
    value != (originalValue ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: icon)
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(.primary)

      TextField(placeholder, text: $value, axis: .vertical)
        .textFieldStyle(.plain)
        .font(.body)
        .padding(12)
        .background {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color(nsColor: .controlBackgroundColor))
        }
        .overlay {
          RoundedRectangle(cornerRadius: 8)
            .strokeBorder(
              isModified ? Color.blue : Color.gray.opacity(0.2),
              lineWidth: isModified ? 1.5 : 1
            )
        }
        .lineLimit(3...8) // 限制最小3行，最大8行，超过滚动
    }
    .padding(16)
    .background {
      RoundedRectangle(cornerRadius: 12)
        .fill(.background)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
    }
  }
}

// MARK: - 空状态视图

struct EmptyDetailView: View {
  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "book.closed")
        .font(.system(size: 64))
        .foregroundStyle(.tertiary)

      Text("拖拽或选择 EPUB 文件开始")
        .font(.title3)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .textBackgroundColor))
  }
}

#Preview {
  EmptyDetailView()
}
