//
//  ContentView.swift
//  epubedit
//
//  Created by seven on 2026/2/9.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
  @EnvironmentObject private var viewModel: EpubEditorViewModel
  @State private var selectedFileID: UUID?
  // 修改：不再使用本地 State，改用 ViewModel 中的共享状态
  @State private var isDragging = false
  @State private var errorAlert: ErrorAlert?
  
  // 新增：控制清空列表确认弹框的状态
  @State private var showClearConfirmation = false
  // 新增：控制侧边栏显示状态
  @State private var columnVisibility: NavigationSplitViewVisibility = .all

  var body: some View {
    // 修改：绑定 columnVisibility
    NavigationSplitView(columnVisibility: $columnVisibility) {
      FileListView(
        files: $viewModel.files,
        selectedFileID: $selectedFileID,
        isDragging: $isDragging,
        onFilesDropped: { urls in
          viewModel.addFiles(urls)
        },
        onFileSelected: { fileID in
          selectedFileID = fileID
        },
        onFileRemoved: { fileID in
          viewModel.removeFile(fileID)
        },
        onAddFiles: {
          // 修改：触发 VM 中的状态
          viewModel.showingFilePicker = true
        },
        // MARK: - 新增：连接右键菜单回调
        onRenameFile: { fileID in
          viewModel.renameFile(for: fileID)
          // 如果重命名失败，显示错误
          if let error = viewModel.lastError {
            errorAlert = ErrorAlert(message: error)
          }
        },
        onMetadataFromFilename: { fileID in
          viewModel.updateMetadataFromFilename(for: fileID)
        },
        // MARK: - 新增：连接重置单个文件回调
        onResetFile: { fileID in
          viewModel.resetFile(for: fileID)
        },
        // MARK: - 新增：连接单个文件处理回调 (右键菜单)
        onProcessFile: { fileID in
            Task {
                await viewModel.processSingleFile(for: fileID)
                if let error = viewModel.lastError {
                    errorAlert = ErrorAlert(message: error)
                }
            }
        },
        // MARK: - 新增：连接清空全部文件回调
        onRemoveAll: {
          viewModel.removeAllFiles()
        }
      ).navigationSplitViewColumnWidth(min: 280, ideal: 300, max: 400)
    } detail: {
      ZStack {
        if let selectedID = selectedFileID,
          let index = viewModel.files.firstIndex(where: { $0.id == selectedID })
        {
          FileDetailView(file: $viewModel.files[index])
        } else if !viewModel.files.isEmpty {
          FileDetailView(file: $viewModel.files[0])
            .onAppear {
              if selectedFileID != viewModel.files[0].id {
                selectedFileID = viewModel.files[0].id
              }
            }
            .id(viewModel.files[0].id)
        } else {
          EmptyDetailView()
        }
      }
      // 1. 修改这里：将 min 从 320 增加到 500 或更大
      // 这样保证内部的横向布局有足够的空间展示
      .navigationSplitViewColumnWidth(min: 550, ideal: 600)
    }
    .navigationTitle("EPUB Editor")
    .navigationSubtitle("\(viewModel.files.count) 个文件")
    .toolbar {
      ToolbarItemGroup(placement: .automatic) {
        ProcessingControlsView(
          isProcessing: viewModel.isProcessing,
          isImporting: viewModel.isImporting,
          hasChanges: viewModel.hasAnyChanges,
          fileCount: viewModel.files.count,
          changedFilesCount: viewModel.changedFilesCount,
          onStartProcessing: {
            Task {
              await viewModel.processAllFiles()
              if let error = viewModel.lastError {
                errorAlert = ErrorAlert(message: error)
              }
            }
          },
          onResetAll: {
            viewModel.resetAllFiles()
          }
          // 注意：ProcessingControlsView 已不再需要批量操作回调
        )

        if viewModel.isImporting || viewModel.isProcessing {
          HStack(spacing: 6) {
            ProgressView()
              .controlSize(.small)
              .progressViewStyle(.circular)

            Text(viewModel.isImporting ? "解析中..." : "处理中...")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.horizontal, 16)
          .transition(.opacity.animation(.easeInOut))
        }
      }
    }
    .fileImporter(
      // 修改：绑定 VM 中的状态
      isPresented: $viewModel.showingFilePicker,
      allowedContentTypes: [UTType(filenameExtension: "epub")!],
      allowsMultipleSelection: true
    ) { result in
      switch result {
      case .success(let urls):
        viewModel.addFiles(urls)
      case .failure(let error):
        errorAlert = ErrorAlert(message: "文件选择失败: \(error.localizedDescription)")
      }
    }
    .onChange(of: viewModel.files.count) { _ in
      ensureSelectionIsValid()
    }
    .alert(item: $errorAlert) { alert in
      Alert(
        title: Text("错误"),
        message: Text(alert.message),
        dismissButton: .default(Text("确定"))
      )
    }
    // 新增：清空列表确认弹框 (对应快捷键操作)
    .alert("确认清空列表", isPresented: $showClearConfirmation) {
      Button("取消", role: .cancel) {}
      Button("清空", role: .destructive) {
        viewModel.removeAllFiles()
      }
    } message: {
      Text("确定要移除列表中的所有文件吗？\n此操作不会删除本地磁盘上的文件。")
    }
    // 2. 新增这里：设置整个 App 窗口的最小尺寸
    .frame(minWidth: 900, minHeight: 400)
    // 核心修改：将所有快捷键逻辑移至 shortcutsView 计算属性中，
    // 避免在此处堆叠过多 .background 导致编译器超时
    .background(shortcutsView)
  }
    
  // MARK: - Shortcuts Extraction
  // 将快捷键逻辑提取出来，帮助编译器快速完成类型检查
  private var shortcutsView: some View {
    Group {
        // 3. 新增：Cmd+Z 触发单个文件重置
        Button("Reset File") {
          if let id = selectedFileID {
            viewModel.resetFile(for: id)
          }
        }
        .keyboardShortcut("z", modifiers: .command)

        // 4. 新增：Cmd+S 触发单个文件执行
        Button("Process Single File") {
          if let id = selectedFileID {
              Task {
                  await viewModel.processSingleFile(for: id)
                  if let error = viewModel.lastError {
                      errorAlert = ErrorAlert(message: error)
                  }
              }
          }
        }
        .keyboardShortcut("s", modifiers: .command)
        
        // 5. 新增：Cmd+Delete 触发移除单个文件
        Button("Remove File") {
          if let id = selectedFileID {
            viewModel.removeFile(id)
          }
        }
        .keyboardShortcut(.delete, modifiers: .command)

        // 6. 新增：Cmd+Shift+Delete 触发清空文件列表 (带确认)
        Button("Remove All Files") {
          if !viewModel.files.isEmpty {
            showClearConfirmation = true
          }
        }
        .keyboardShortcut(.delete, modifiers: [.command, .shift])
        
        // 7. 新增：Cmd+J 切换侧边栏显示/隐藏
        Button("Toggle Sidebar") {
          withAnimation {
            columnVisibility = (columnVisibility == .all) ? .detailOnly : .all
          }
        }
        .keyboardShortcut("j", modifiers: .command)
    }
    .hidden()
  }

  private func ensureSelectionIsValid() {
    if viewModel.files.isEmpty {
      selectedFileID = nil
      return
    }
    if selectedFileID == nil || !viewModel.files.contains(where: { $0.id == selectedFileID }) {
      selectedFileID = viewModel.files.first?.id
    }
  }
}

struct ErrorAlert: Identifiable {
  let id = UUID()
  let message: String
}

#Preview {
  ContentView()
    .environmentObject(EpubEditorViewModel())
}
