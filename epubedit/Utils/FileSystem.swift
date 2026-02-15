import Foundation

struct FileSystem {
  static let fm = FileManager.default

  static func createTempDirectory() throws -> URL {
    let tempDir = fm.temporaryDirectory.appendingPathComponent("epubedit-\(UUID().uuidString)")
    do {
      try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
      return tempDir
    } catch {
      throw NSError(
        domain: "FileSystem",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "无法创建临时目录: \(error.localizedDescription)"]
      )
    }
  }

  @discardableResult
  static func removeDirectory(at url: URL) -> Bool {
    do {
      try fm.removeItem(at: url)
      return true
    } catch {
      fputs("警告：清理临时目录失败 (\(url.path)): \(error.localizedDescription)\n", stderr)
      return false
    }
  }

  static func exists(at path: String) -> Bool {
    return fm.fileExists(atPath: path)
  }

  static func isDirectory(at path: String) -> Bool {
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
      return false
    }
    return isDir.boolValue
  }

  static func fileSize(at path: String) -> Int64? {
    guard let attrs = try? fm.attributesOfItem(atPath: path),
      let size = attrs[.size] as? NSNumber
    else {
      return nil
    }
    return size.int64Value
  }
}
