//
//  FileListView.swift
//  epubedit
//

import SwiftUI
import UniformTypeIdentifiers

struct FileListView: View {
  @Binding var files: [EpubFile]
  @Binding var selectedFileID: UUID?
  @Binding var isDragging: Bool

  let onFilesDropped: ([URL]) -> Void
  let onFileSelected: (UUID) -> Void
  let onFileRemoved: (UUID) -> Void
  let onAddFiles: () -> Void
  // 新增：右键操作的回调
  let onRenameFile: (UUID) -> Void
  let onMetadataFromFilename: (UUID) -> Void
  // 新增：单个文件重置回调
  let onResetFile: (UUID) -> Void
  // 新增：单个文件执行回调
  let onProcessFile: (UUID) -> Void
  // 新增：清空所有文件的回调
  let onRemoveAll: () -> Void

  @State private var showClearConfirmation = false
  // 核心修改 1：新增用于确认重置的文件状态
  @State private var fileConfirmingReset: EpubFile?

  var body: some View {
    VStack(spacing: 0) {
      // 顶部拖拽区域
      if files.isEmpty {
        DropZoneView(isDragging: isDragging, onAddFiles: onAddFiles)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        // 文件列表
        List(selection: $selectedFileID) {
          ForEach(files) { file in
            // 这里传入 isSelected 状态，判断当前文件ID是否等于选中的ID
            FileRowView(file: file, isSelected: selectedFileID == file.id)
              .tag(file.id)
              .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
              .listRowSeparator(.hidden)
              .contextMenu {
                // MARK: - 新增的右键菜单项
                
                // 新增：立即执行修改
                Button {
                    onProcessFile(file.id)
                } label: {
                    Label("立即执行修改", systemImage: "play.fill")
                }
                .disabled(!file.hasChanges) // 只有有修改时才可用
                
                Divider()
                
                Button {
                  onMetadataFromFilename(file.id)
                } label: {
                  Label("从文件名填入信息", systemImage: "doc.text.magnifyingglass")
                }
                
                Button {
                  onRenameFile(file.id)
                } label: {
                  Label("重命名文件 (书名-作者)", systemImage: "pencil.and.outline")
                }
                
                // 单独的重置按钮
                Button {
                  // 核心修改 2：点击不直接重置，而是赋值给状态以触发弹框
                  fileConfirmingReset = file
                } label: {
                  Label("重置修改", systemImage: "arrow.counterclockwise")
                }
                .disabled(!file.hasChanges)
                
                Divider()
                
                Button(role: .destructive) {
                  onFileRemoved(file.id)
                } label: {
                  Label("移除", systemImage: "trash")
                }

                Button {
                  NSWorkspace.shared.selectFile(file.url.path, inFileViewerRootedAtPath: "")
                } label: {
                  Label("在访达中显示", systemImage: "folder")
                }
              }
          }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)

        // 底部按钮区域：添加文件 + 清空
        Divider()

        HStack(spacing: 0) {
          // 左侧：添加文件按钮
          Button(action: onAddFiles) {
            Label("添加文件", systemImage: "plus.circle.fill")
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
              .contentShape(Rectangle()) // 扩大点击区域
          }
          .buttonStyle(.borderless)
          
          Divider()
            .frame(height: 24)
          
          // 右侧：清空文件按钮
          Button(action: {
            showClearConfirmation = true
          }) {
            Label("清空", systemImage: "trash")
              .frame(maxWidth: .infinity)
              .padding(.vertical, 12)
              .contentShape(Rectangle())
          }
          .buttonStyle(.borderless)
          .disabled(files.isEmpty)
        }
        .controlSize(.large)
      }
    }
    .background(Color(nsColor: .controlBackgroundColor))
    .onDrop(of: [.fileURL], isTargeted: $isDragging) { providers in
      handleDrop(providers)
      return true
    }
    .alert("确认清空列表", isPresented: $showClearConfirmation) {
      Button("取消", role: .cancel) {}
      Button("清空", role: .destructive) {
        onRemoveAll()
      }
    } message: {
      Text("确定要移除列表中的所有文件吗？\n此操作不会删除本地磁盘上的文件。")
    }
    // 核心修改 3：增加重置确认弹框
    .alert(item: $fileConfirmingReset) { file in
      Alert(
        title: Text("确认重置文件"),
        message: Text("确定要丢弃对 \"\(file.displayName)\" 的所有未保存修改吗？\n\n此操作不可恢复。"),
        primaryButton: .destructive(Text("重置")) {
          onResetFile(file.id)
        },
        secondaryButton: .cancel(Text("取消"))
      )
    }
  }

  private func handleDrop(_ providers: [NSItemProvider]) {
    var urls: [URL] = []
    let group = DispatchGroup()

    for provider in providers {
      group.enter()
      provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
        defer { group.leave() }

        if let error = error {
          print("❌ 加载拖拽项错误: \(error)")
          return
        }

        if let data = item as? Data,
          let url = URL(dataRepresentation: data, relativeTo: nil)
        {

          // 检查文件扩展名
          if url.pathExtension.lowercased() == "epub" {
            urls.append(url)
            print("✅ 拖拽文件: \(url.lastPathComponent)")
          } else {
            print("⚠️ 跳过非 EPUB 文件: \(url.lastPathComponent)")
          }
        }
      }
    }

    group.notify(queue: .main) {
      if !urls.isEmpty {
        onFilesDropped(urls)
      }
    }
  }
}

struct FileRowView: View {
  let file: EpubFile
  let isSelected: Bool  // 新增属性接收选中状态

  var body: some View {
    HStack(spacing: 12) {
      // 状态图标
      Image(systemName: file.processingStatus.icon)
        .foregroundStyle(isSelected ? .white : file.processingStatus.color)
        .font(.title3)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 4) {
        Text(file.displayName)
          .font(.system(.body, design: .rounded))
          .lineLimit(1)

        Text(file.fileSize)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if file.hasChanges {
        Image(systemName: "pencil.circle.fill")
          // 修改此处逻辑：如果被选中则显示白色，否则显示蓝色
          .foregroundStyle(isSelected ? .white : .blue)
          .font(.caption)
      }
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
  }
}

struct DropZoneView: View {
  let isDragging: Bool
  let onAddFiles: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: "arrow.down.doc.fill")
        .font(.system(size: 48))
        .foregroundStyle(.blue.gradient)

      Text("拖拽 EPUB 文件到这里")
        .font(.title3)
        .fontWeight(.medium)

      Text("或")
        .foregroundStyle(.secondary)

      Button(action: onAddFiles) {
        Label("选择文件", systemImage: "folder.badge.plus")
          .font(.body)
          .padding(.horizontal, 24)
          .padding(.vertical, 10)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background {
      RoundedRectangle(cornerRadius: 16)
        .fill(Color.blue.opacity(isDragging ? 0.1 : 0.05))
        .overlay {
          RoundedRectangle(cornerRadius: 16)
            .strokeBorder(
              style: StrokeStyle(lineWidth: 2, dash: [8, 4])
            )
            .foregroundStyle(.blue.opacity(isDragging ? 0.5 : 0.2))
        }
    }
    .padding(20)
    .animation(.spring(response: 0.3), value: isDragging)
  }
}

#Preview {
  FileListView(
    files: .constant([]),
    selectedFileID: .constant(nil),
    isDragging: .constant(false),
    onFilesDropped: { _ in },
    onFileSelected: { _ in },
    onFileRemoved: { _ in },
    onAddFiles: {},
    onRenameFile: { _ in },
    onMetadataFromFilename: { _ in },
    onResetFile: { _ in },
    onProcessFile: { _ in },
    onRemoveAll: {}
  )
  .frame(width: 300, height: 600)
}
