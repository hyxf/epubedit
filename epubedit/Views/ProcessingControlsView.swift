//
//  ProcessingControlsView.swift
//  epubedit
//

import SwiftUI

struct ProcessingControlsView: View {
  let isProcessing: Bool
  let isImporting: Bool
  let hasChanges: Bool
  let fileCount: Int
  let changedFilesCount: Int
  let onStartProcessing: () -> Void
  let onResetAll: () -> Void

  @State private var showResetConfirmation = false

  var body: some View {
    HStack(spacing: 8) {
      // 恢复：移除批量工具，只保留重置和开始按钮

      // 重置全部按钮
      Button(action: {
        showResetConfirmation = true
      }) {
        Label("重置全部", systemImage: "arrow.counterclockwise")
      }
      .buttonStyle(.borderedProminent)
      .disabled(isProcessing || isImporting || !hasChanges)
      .alert("确认重置", isPresented: $showResetConfirmation) {
        Button("取消", role: .cancel) {}
        Button("重置", role: .destructive) {
          onResetAll()
        }
      } message: {
        Text("将重置 \(changedFilesCount) 个文件的所有未保存修改\n\n此操作不可恢复，确定要继续吗？")
      }
      // 新增：Cmd+Shift+Z 触发批量重置
      .keyboardShortcut("z", modifiers: [.command, .shift])

      // 开始处理按钮
      Button(action: onStartProcessing) {
        Label(
          isProcessing ? "处理中..." : "开始处理\(fileCount > 0 ? " (\(fileCount))" : "")",
          systemImage: isProcessing ? "arrow.triangle.2.circlepath" : "play.fill"
        )
      }
      .buttonStyle(.borderedProminent)
      .disabled(isProcessing || isImporting || fileCount == 0 || !hasChanges)
      // 新增：Cmd+Shift+S 触发批量执行
      .keyboardShortcut("s", modifiers: [.command, .shift])
    }.padding(.horizontal, 10)
  }
}
