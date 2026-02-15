// [保持原有 OpfEditor 代码]
import Foundation

class OpfEditor {
  private let doc: XMLDocument
  private let opfURL: URL
  private let namespaces: [String: String]

  init(opfURL: URL) throws {
    self.opfURL = opfURL
    self.doc = try XMLDocument(contentsOf: opfURL, options: [.nodePreserveAll])

    self.namespaces = [
      "opf": "http://www.idpf.org/2007/opf",
      "dc": "http://purl.org/dc/elements/1.1/",
      "dcterms": "http://purl.org/dc/terms/",
    ]
  }

  func save() throws {
    let data = doc.xmlData(options: [.nodePrettyPrint])
    try data.write(to: opfURL)
  }

  func updateTitle(_ newTitle: String) {
    guard let root = doc.rootElement() else { return }

    let titleNodes = executeXPath(xpath: "//*[local-name()='title']", in: root)

    if let firstTitle = titleNodes.first as? XMLElement {
      firstTitle.setStringValue(newTitle, resolvingEntities: true)
    } else {
      let metadataNode = findOrCreateMetadata(in: root)
      let newElement = XMLElement(name: "dc:title", stringValue: newTitle)

      if metadataNode.resolveNamespace(forName: "dc") == nil {
        newElement.addNamespace(
          XMLNode.namespace(withName: "dc", stringValue: namespaces["dc"]!) as! XMLNode)
      }

      metadataNode.addChild(newElement)
    }
  }

  func updateAuthor(_ newAuthor: String) {
    guard let root = doc.rootElement() else { return }

    let creatorNodes = executeXPath(xpath: "//*[local-name()='creator']", in: root)

    if let firstCreator = creatorNodes.first as? XMLElement {
      firstCreator.setStringValue(newAuthor, resolvingEntities: true)
    } else {
      let metadataNode = findOrCreateMetadata(in: root)
      let newElement = XMLElement(name: "dc:creator", stringValue: newAuthor)

      if metadataNode.resolveNamespace(forName: "dc") == nil {
        newElement.addNamespace(
          XMLNode.namespace(withName: "dc", stringValue: namespaces["dc"]!) as! XMLNode)
      }

      metadataNode.addChild(newElement)
    }
  }

  func updateCover(newCoverFileName: String, mimeType: String) {
    guard let root = doc.rootElement() else { return }

    let metadataNode = findOrCreateMetadata(in: root)
    let manifestNode = findOrCreateManifest(in: root)

    let newCoverId = "cover-image-\(UUID().uuidString.prefix(6).lowercased())"

    let itemsWithCoverProp = executeXPath(
      xpath: "//*[local-name()='item'][contains(@properties, 'cover-image')]",
      in: manifestNode
    )

    for node in itemsWithCoverProp {
      guard let el = node as? XMLElement else { continue }
      if let props = el.attribute(forName: "properties")?.stringValue {
        let newProps = props.replacingOccurrences(of: "cover-image", with: "")
          .trimmingCharacters(in: .whitespaces)
        if newProps.isEmpty {
          el.removeAttribute(forName: "properties")
        } else {
          setAttr(node: el, name: "properties", value: newProps)
        }
      }
    }

    let newItem = XMLElement(name: "item")
    setAttr(node: newItem, name: "id", value: newCoverId)
    setAttr(node: newItem, name: "href", value: newCoverFileName)
    setAttr(node: newItem, name: "media-type", value: mimeType)
    setAttr(node: newItem, name: "properties", value: "cover-image")
    manifestNode.addChild(newItem)

    let coverMetaNodes = executeXPath(
      xpath: "//*[local-name()='meta'][@name='cover']", in: metadataNode)

    if let coverMeta = coverMetaNodes.first as? XMLElement {
      setAttr(node: coverMeta, name: "content", value: newCoverId)
    } else {
      let newMeta = XMLElement(name: "meta")
      setAttr(node: newMeta, name: "name", value: "cover")
      setAttr(node: newMeta, name: "content", value: newCoverId)
      metadataNode.addChild(newMeta)
    }
  }

  private func executeXPath(xpath: String, in element: XMLElement) -> [XMLNode] {
    do {
      return try element.nodes(forXPath: xpath)
    } catch {
      return []
    }
  }

  private func setAttr(node: XMLElement, name: String, value: String) {
    if let attr = node.attribute(forName: name) {
      attr.stringValue = value
    } else {
      node.addAttribute(XMLNode.attribute(withName: name, stringValue: value) as! XMLNode)
    }
  }

  private func findOrCreateMetadata(in root: XMLElement) -> XMLElement {
    let metadataNodes = executeXPath(xpath: "//*[local-name()='metadata']", in: root)

    if let metadata = metadataNodes.first as? XMLElement {
      return metadata
    }

    let metadata = XMLElement(name: "metadata")

    if root.resolveNamespace(forName: "dc") == nil {
      metadata.addNamespace(
        XMLNode.namespace(withName: "dc", stringValue: namespaces["dc"]!) as! XMLNode)
    }

    if let manifestIndex = root.children?.firstIndex(where: {
      ($0 as? XMLElement)?.name == "manifest"
    }) {
      root.insertChild(metadata, at: manifestIndex)
    } else {
      root.addChild(metadata)
    }

    return metadata
  }

  private func findOrCreateManifest(in root: XMLElement) -> XMLElement {
    let manifestNodes = executeXPath(xpath: "//*[local-name()='manifest']", in: root)

    if let manifest = manifestNodes.first as? XMLElement {
      return manifest
    }

    let manifest = XMLElement(name: "manifest")
    root.addChild(manifest)
    return manifest
  }
}
