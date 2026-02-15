//
//  epubeditApp.swift
//  epubedit
//
//  Created by seven on 2026/2/9.
//

import SwiftUI

@main
struct epubeditApp: App {
  @StateObject private var viewModel = EpubEditorViewModel()
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(viewModel)
        .onAppear {
          // 注入 VM 给 AppDelegate (如果后续需要 Delegate 处理菜单等逻辑)
          appDelegate.setViewModel(viewModel)
        }
        // MARK: - 核心修复：处理文件打开
        // 1. 无论是冷启动还是热启动，文件 URL 都会传到这里。
        // 2. 添加这个修饰符后，SwiftUI 会倾向于复用当前窗口，从而实现 "单窗口" 模式。
        .onOpenURL { url in
          print("🔗 [SwiftUI] onOpenURL 收到文件: \(url.path)")
          // 激活 App 窗口到最前
          NSApp.activate(ignoringOtherApps: true)
          // 直接调用 ViewModel 处理
          viewModel.addFiles([url])
        }
    }
    .windowStyle(.hiddenTitleBar)
    .windowToolbarStyle(.unified)
    .commands {
      // 修复：替换 "新建" 组，同时禁用新建并添加打开功能
      CommandGroup(replacing: .newItem) {
        Button("打开...") {
          viewModel.showingFilePicker = true
        }
        .keyboardShortcut("o", modifiers: .command)
      }
    }
    // MARK: - 核心修复：允许所有事件
    // 必须设置为 "*"，否则冷启动时（右键->打开方式），SwiftUI 会因为
    // 事件 ID 不匹配而拒绝创建窗口，导致 App 运行了但没有 UI。
    .handlesExternalEvents(matching: Set(arrayLiteral: "*"))
  }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, NSApplicationDelegate {

  private weak var viewModel: EpubEditorViewModel?

  func setViewModel(_ vm: EpubEditorViewModel) {
    self.viewModel = vm
  }

  // MARK: - 注意
  // 当在 SwiftUI View 中使用了 .onOpenURL 后，这个 application(_:open:) 方法
  // 通常不会再被调用（事件被 SwiftUI 拦截了）。
  // 但保留这个方法作为一个 "安全网" 是个好习惯，以防某些特殊情况绕过了 SwiftUI 的生命周期。
  func application(_ application: NSApplication, open urls: [URL]) {
    print("📥 [AppDelegate] (Fallback) 收到 \(urls.count) 个文件")

    let epubURLs = urls.filter { $0.pathExtension.lowercased() == "epub" }
    guard !epubURLs.isEmpty else { return }

    NSApp.activate(ignoringOtherApps: true)

    // 如果 ViewModel 已经存在，直接处理
    if let vm = viewModel {
      vm.addFiles(epubURLs)
    } else {
      // 极其罕见的情况：AppDelegate 先于 SwiftUI View 初始化完成并收到文件。
      // 在现代 SwiftUI App 生命周期中，通常 .onOpenURL 会处理冷启动，
      // 这里仅作简单的日志或备用处理即可。
      print("⚠️ [AppDelegate] ViewModel 未就绪，建议依赖 onOpenURL 处理冷启动")
    }
  }
}
