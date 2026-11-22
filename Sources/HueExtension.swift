import AppKit
import OSLog
import TunaKit

extension TypeID {
  static let hueGroup = TypeID("de.bjesuiter.tuna.type.hue-group")
}

@objc(HueExtension)
public final class HueExtension: Extension {
  public override var declaration: ExtensionDeclaration? {
    ExtensionDeclaration(
      metadata: ExtensionMetadata(
        displayName: "Hue Control",
        author: "Benjamin Jesuiter",
        description: "Find Philips Hue rooms and zones and turn their lights on or off.",
        iconName: "lightbulb"
      ),
      compatibility: ExtensionDeclarationCompatibility(minTuna: "0.113", minTunaKit: "1.23.0"),
      settings: HueSettings.definitions,
      catalogs: [
        CatalogDeclaration(
          id: "hue.groups", type: HueCatalog.self, name: "Hue Groups",
          presentation: .source, enabledByDefault: true, initialGlobalScope: .all
        ),
      ],
      actionCatalogs: [
        ActionCatalogDeclaration(id: "hue.actions", type: HueActions.self, name: "Hue Actions"),
      ],
      typeRegistrations: [
        TypeRegistrationDefinition(typeID: .hueGroup, displayName: "Hue Groups", inheritsFrom: [.entity]),
      ],
      defaultActionRankings: [
        DefaultActionRankingDefinition(
          typeID: .hueGroup,
          actions: ["on", "off"].map { ActionReference(catalogIdentifier: "hue.actions", actionID: $0) }
        ),
      ]
    )
  }
}

enum HueSettings {
  private static let address = CatalogSettingDefinition(
    key: "BridgeAddress", type: .string, label: "Bridge address", defaultValue: "",
    description: "The local IPv4 address or hostname."
  )
  private static let bridgeID = CatalogSettingDefinition(
    key: "BridgeID", type: .string, label: "Bridge ID", defaultValue: "",
    description: "The 16-character hexadecimal ID used by the bridge certificate."
  )
  private static let key = CatalogSettingDefinition(
    key: "ApplicationKey", type: .secret, label: "Application key", defaultValue: "",
    description: "The Hue application key, stored in the macOS Keychain."
  )
  private static let caPath = CatalogSettingDefinition(
    key: "RootCAPath", type: .string, label: "Hue root CA PEM path", defaultValue: "",
    description: "Path to the official Signify CA PEM file for your bridge."
  )

  static let definitions = [address, bridgeID, key, caPath]

  static func bridge() throws -> HueBridge {
    let store = CatalogSettingStore(
      catalogIdentifier: Bundle(for: HueExtension.self).bundleIdentifier ?? "de.bjesuiter.tuna.hue"
    )
    let path = store.stringValue(for: caPath).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty, let pem = try? String(
      contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8
    ) else {
      throw HueError.configuration("Set the Hue root CA PEM path in Hue Control settings.")
    }
    return try HueBridge(
      address: store.stringValue(for: address).trimmingCharacters(in: .whitespacesAndNewlines),
      id: store.stringValue(for: bridgeID).trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      key: store.secretValue(for: key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
      caPEM: pem
    )
  }
}

@MainActor
public final class HueCatalog: Catalog, CatalogDiagnosticsReporting {
  public let identifier: String
  public let name: String
  public private(set) var objects: [CatalogItem] = []

  private let logger = Logger(subsystem: "de.bjesuiter.tuna.hue", category: "catalog")
  private var scanID = UUID()
  private var status = "Waiting for first scan"

  public required init(definition: CatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
  }

  public func scan() async {
    let currentScan = UUID()
    scanID = currentScan
    do {
      let bridge = try HueSettings.bridge()
      let groups = try await bridge.groups()
      guard scanID == currentScan, !Task.isCancelled else { return }
      objects = groups.map { HueGroupItem(group: $0, bridgeID: bridge.id) }
      status = "Loaded \(groups.count) Hue groups"
    } catch {
      guard scanID == currentScan, !Task.isCancelled else { return }
      objects = []
      status = error.localizedDescription
      logger.error("Hue catalog scan failed: \(self.status, privacy: .private)")
    }
    reportScanFinished()
  }

  public func diagnosticsSnapshot() -> CatalogDiagnosticsSnapshot {
    CatalogDiagnosticsSnapshot(metrics: ["Hue": .text(status)])
  }
}

private final class HueGroupItem: CatalogEntity, @unchecked Sendable {
  let group: HueGroup
  let bridgeID: String

  init(group: HueGroup, bridgeID: String) {
    self.group = group
    self.bridgeID = bridgeID
    super.init(id: "\(bridgeID)/\(group.kind.rawValue)/\(group.id)", title: group.name, path: nil)
    typeID = .hueGroup
  }

  override var detail: String? { group.kind.label }

  override func placeholderPreview(maxDimension: CGFloat) -> CatalogItemPreview {
    .systemSymbol(group.kind == .room ? "lightbulb" : "lightbulb.2", tintColor: .systemOrange)
  }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    placeholderPreview(maxDimension: maxDimension)
  }
}

@MainActor
public final class HueActions: ActionCatalog {
  public let identifier: String
  public let name: String
  public private(set) lazy var actions: [CatalogAction] = [
    Self.powerAction(id: "on", title: "Turn On", symbol: "lightbulb.fill", on: true),
    Self.powerAction(id: "off", title: "Turn Off", symbol: "lightbulb.slash", on: false),
  ]

  public required init(definition: ActionCatalogDefinition) {
    identifier = definition.identifier
    name = definition.name
  }

  private static func powerAction(id: String, title: String, symbol: String, on: Bool) -> CatalogAction {
    let action = PredicateAwareAction(id: id, title: title) { subject, _ in
      guard let item = subject as? HueGroupItem else {
        return .failure("Choose a Hue room or zone.")
      }
      do {
        let bridge = try HueSettings.bridge()
        guard bridge.id == item.bridgeID else { throw HueError.bridgeChanged }
        try await bridge.setPower(on, lightID: item.group.lightID)
        return .success
      } catch {
        return .failure(error.localizedDescription)
      }
    }
    action.supportedSubjectTypes = [.hueGroup]
    action.subjectPredicate = { $0 is HueGroupItem }
    action.systemSymbolName = symbol
    action.executionPolicy = .keepVisible
    return action
  }
}
