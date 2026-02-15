//
//  EpubMetadataExtractor.swift
//  epubedit
//

import Foundation
import ZIPFoundation

struct EpubMetadata {
  var title: String?
  var author: String?
  var publisher: String?
  var language: String?
  var identifier: String?
  var description: String?
  var coverData: Data?
  var coverExtension: String? // 新增：存储封面的原始拓展名
}

class EpubMetadataExtractor {

  static func extract(from url: URL, hasAccess: Bool = false) -> EpubMetadata? {
    var metadata = EpubMetadata()

    let needsStopAccessing: Bool
    if hasAccess {
      needsStopAccessing = false
    } else {
      needsStopAccessing = url.startAccessingSecurityScopedResource()
    }

    defer {
      if needsStopAccessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    guard
      let tempDir = try? FileManager.default.url(
        for: .itemReplacementDirectory,
        in: .userDomainMask,
        appropriateFor: url,
        create: true
      )
    else {
      print("❌ 无法创建临时目录")
      return nil
    }

    defer {
      try? FileManager.default.removeItem(at: tempDir)
    }

    do {
      try FileManager.default.unzipItem(at: url, to: tempDir)
    } catch {
      print("❌ 解压失败: \(error.localizedDescription)")
      return nil
    }

    let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
    guard let containerData = try? Data(contentsOf: containerPath),
      let containerDoc = try? XMLDocument(data: containerData),
      let rootFileNode = try? containerDoc.nodes(forXPath: "//*[local-name()='rootfile']").first
        as? XMLElement,
      let opfPath = rootFileNode.attribute(forName: "full-path")?.stringValue
    else {
      print("❌ 无法读取 container.xml")
      return nil
    }

    let opfURL = tempDir.appendingPathComponent(opfPath)
    guard let opfData = try? Data(contentsOf: opfURL),
      let opfDoc = try? XMLDocument(data: opfData)
    else {
      print("❌ 无法读取 OPF 文件")
      return nil
    }

    if let titleNodes = try? opfDoc.nodes(forXPath: "//*[local-name()='title']"),
      let titleNode = titleNodes.first,
      let title = titleNode.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !title.isEmpty
    {
      metadata.title = title
      print("📖 提取书名: \(title)")
    }

    if let authorNodes = try? opfDoc.nodes(forXPath: "//*[local-name()='creator']"),
      let authorNode = authorNodes.first,
      let author = authorNode.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
      !author.isEmpty
    {
      metadata.author = author
      print("✍️ 提取作者: \(author)")
    }
    
    if let pubNodes = try? opfDoc.nodes(forXPath: "//*[local-name()='publisher']"),
       let pubNode = pubNodes.first,
       let pub = pubNode.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
       !pub.isEmpty
    {
      metadata.publisher = pub
      print("🏢 提取出版社: \(pub)")
    }
    
    if let langNodes = try? opfDoc.nodes(forXPath: "//*[local-name()='language']"),
       let langNode = langNodes.first,
       let lang = langNode.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
       !lang.isEmpty
    {
      metadata.language = lang
      print("🌐 提取语言: \(lang)")
    }
    
    if let idNodes = try? opfDoc.nodes(forXPath: "//*[local-name()='identifier']"),
       let idNode = idNodes.first,
       let idVal = idNode.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
       !idVal.isEmpty
    {
      metadata.identifier = idVal
      print("🔑 提取ID: \(idVal)")
    }
    
    if let descNodes = try? opfDoc.nodes(forXPath: "//*[local-name()='description']"),
       let descNode = descNodes.first,
       let desc = descNode.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
       !desc.isEmpty
    {
      metadata.description = desc
      print("📝 提取简介: \(desc.prefix(20))...")
    }

    // 修改：同时获取数据和后缀
    if let coverResult = extractCover(from: opfDoc, baseURL: opfURL.deletingLastPathComponent()) {
        metadata.coverData = coverResult.data
        metadata.coverExtension = coverResult.ext
    }

    return metadata
  }

  // 修改：返回 (Data, String)? 元组
  private static func extractCover(from opfDoc: XMLDocument, baseURL: URL) -> (data: Data, ext: String)? {
    if let coverItems = try? opfDoc.nodes(
      forXPath: "//*[local-name()='item'][@properties='cover-image']"),
      let coverItem = coverItems.first as? XMLElement,
      let href = coverItem.attribute(forName: "href")?.stringValue
    {
      return loadImageData(href: href, baseURL: baseURL)
    }

    if let metaNodes = try? opfDoc.nodes(forXPath: "//*[local-name()='meta'][@name='cover']"),
      let metaNode = metaNodes.first as? XMLElement,
      let coverId = metaNode.attribute(forName: "content")?.stringValue,
      let itemNodes = try? opfDoc.nodes(forXPath: "//*[local-name()='item'][@id='\(coverId)']"),
      let itemNode = itemNodes.first as? XMLElement,
      let href = itemNode.attribute(forName: "href")?.stringValue
    {
      return loadImageData(href: href, baseURL: baseURL)
    }

    let commonCoverNames = ["cover.jpg", "cover.jpeg", "cover.png", "Cover.jpg", "Cover.png"]
    for name in commonCoverNames {
      let coverURL = baseURL.appendingPathComponent(name)
      if FileManager.default.fileExists(atPath: coverURL.path),
        let data = try? Data(contentsOf: coverURL)
      {
        print("🖼️ 找到封面: \(name)")
        let ext = (name as NSString).pathExtension
        return (data, ext)
      }
    }

    print("⚠️ 未找到封面")
    return nil
  }

  private static func loadImageData(href: String, baseURL: URL) -> (Data, String)? {
    let decodedHref = href.removingPercentEncoding ?? href
    let imageURL = baseURL.appendingPathComponent(decodedHref)

    if let data = try? Data(contentsOf: imageURL) {
      print("🖼️ 提取封面: \(decodedHref)")
      let ext = (decodedHref as NSString).pathExtension
      return (data, ext)
    }

    return nil
  }
}
