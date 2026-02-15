//
//  ProcessingOverlayView.swift
//  epubedit
//

import SwiftUI

struct ProcessingOverlayView: View {
  let progress: Double
  let currentFile: String?
  let processedFiles: [UUID: ProcessingStatus]
  let isCompleted: Bool
  let onDismiss: () -> Void

  var successCount: Int {
    processedFiles.values.filter { $0 == .success }.count
  }

  var failedCount: Int {
    processedFiles.values.filter { $0 == .failed }.count
  }

  var body: some View {
    VStack(spacing: 24) {
      if isCompleted {
        // 完成状态
        VStack(spacing: 20) {
          Image(
            systemName: failedCount > 0
              ? "checkmark.circle.badge.xmark.fill" : "checkmark.circle.fill"
          )
          .font(.system(size: 64))
          .foregroundStyle(failedCount > 0 ? .orange : .green)

          Text(failedCount > 0 ? "处理完成（部分失败）" : "全部处理完成")
            .font(.title2)
            .fontWeight(.bold)

          // 统计信息
          HStack(spacing: 32) {
            StatBadge(
              icon: "checkmark.circle.fill",
              color: .green,
              count: successCount,
              label: "成功"
            )

            if failedCount > 0 {
              StatBadge(
                icon: "xmark.circle.fill",
                color: .red,
                count: failedCount,
                label: "失败"
              )
            }
          }
          .padding(.top, 8)

          Button(action: onDismiss) {
            Text("完成")
              .font(.headline)
              .frame(width: 120)
              .padding(.vertical, 12)
          }
          .buttonStyle(.borderedProminent)
          .controlSize(.large)
          .padding(.top, 12)
        }
      } else {
        // 处理中状态
        ZStack {
          Circle()
            .stroke(Color.gray.opacity(0.2), lineWidth: 8)
            .frame(width: 100, height: 100)

          Circle()
            .trim(from: 0, to: progress)
            .stroke(
              LinearGradient(
                colors: [.blue, .cyan],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
              style: StrokeStyle(lineWidth: 8, lineCap: .round)
            )
            .frame(width: 100, height: 100)
            .rotationEffect(.degrees(-90))
            .animation(.easeInOut, value: progress)

          Text("\(Int(progress * 100))%")
            .font(.title2)
            .fontWeight(.bold)
        }

        // 当前处理文件
        if let current = currentFile {
          VStack(spacing: 8) {
            Text("正在处理")
              .font(.caption)
              .foregroundStyle(.secondary)

            Text(current)
              .font(.body)
              .fontWeight(.medium)
              .lineLimit(1)
          }
        }

        // 统计信息
        HStack(spacing: 24) {
          StatBadge(
            icon: "checkmark.circle.fill",
            color: .green,
            count: successCount,
            label: "成功"
          )

          if failedCount > 0 {
            StatBadge(
              icon: "xmark.circle.fill",
              color: .red,
              count: failedCount,
              label: "失败"
            )
          }
        }
      }
    }
    .padding(40)
    .background {
      RoundedRectangle(cornerRadius: 20)
        .fill(.ultraThinMaterial)
        .shadow(color: .black.opacity(0.2), radius: 20, y: 10)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black.opacity(0.3))
  }
}

struct StatBadge: View {
  let icon: String
  let color: Color
  let count: Int
  let label: String

  var body: some View {
    VStack(spacing: 4) {
      HStack(spacing: 4) {
        Image(systemName: icon)
          .foregroundStyle(color)
        Text("\(count)")
          .fontWeight(.semibold)
      }
      .font(.title3)

      Text(label)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }
}

#Preview {
  ProcessingOverlayView(
    progress: 1.0,
    currentFile: nil,
    processedFiles: [
      UUID(): .success,
      UUID(): .success,
      UUID(): .failed,
    ],
    isCompleted: true,
    onDismiss: {}
  )
}
