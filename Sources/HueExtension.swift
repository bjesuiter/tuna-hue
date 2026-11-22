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

  private static let store = CatalogSettingStore(
    catalogIdentifier: Bundle(for: HueExtension.self).bundleIdentifier ?? "de.bjesuiter.tuna.hue"
  )

  static func bridge() throws -> HueBridge {
    try bridge(
      address: store.stringValue(for: address), id: store.stringValue(for: bridgeID),
      key: store.secretValue(for: key) ?? "", path: store.stringValue(for: caPath)
    )
  }

  private static func bridge(address: String, id: String, key: String, path: String) throws -> HueBridge {
    let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
    let pem: String
    if path.isEmpty {
      pem = hueRootCertificates
    } else {
      guard let contents = try? String(
        contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8
      ) else {
        throw HueError.configuration("Check the Hue root CA PEM path in Hue Control settings.")
      }
      pem = contents
    }
    return try HueBridge(
      address: address.trimmingCharacters(in: .whitespacesAndNewlines),
      id: id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      key: key.trimmingCharacters(in: .whitespacesAndNewlines),
      caPEM: pem
    )
  }

  @MainActor
  static func connect() async throws -> Bool {
    var manual = false
    while true {
      let result = try await (manual ? connectManually() : connectAutomatically())
      switch result {
      case .connected: return true
      case .cancelled: return false
      case .switchMode: manual.toggle()
      case .refresh: break
      }
    }
  }

  private enum ConnectionResult {
    case connected, cancelled, switchMode, refresh
  }

  @MainActor
  private static func connectAutomatically() async throws -> ConnectionResult {
    let prompt = HuePairingPrompt()
    prompt.show()
    defer {
      prompt.cancelPairing = nil
      prompt.close()
    }
    let pairing = Task {
      let bridges = try await DiscoveredHueBridge.discover()
      try Task.checkCancellation()
      let bridge = await prompt.choose(from: bridges)
      try Task.checkCancellation()
      guard let bridge else {
        return false
      }
      let id = bridge.id.lowercased()
      let address = bridge.internalipaddress
      prompt.message.stringValue = "Press the physical link button on your Hue Bridge."
      let client = try HueBridge(address: address, id: id, caPEM: hueRootCertificates)
      let key = try await client.pair()
      try Task.checkCancellation()
      prompt.message.stringValue = "Verifying the bridge connection…"
      try await save(address: address, id: id, key: key, path: "")
      return true
    }
    prompt.cancelPairing = { pairing.cancel() }
    do {
      let connected = try await pairing.value
      if prompt.refreshRequested { return .refresh }
      return connected ? .connected : .cancelled
    } catch {
      if prompt.manual { return .switchMode }
      if prompt.refreshRequested { return .refresh }
      if pairing.isCancelled { return .cancelled }
      prompt.close()
      let alert = NSAlert()
      alert.messageText = "Couldn’t connect to Hue Bridge"
      alert.informativeText = error.localizedDescription
      alert.addButton(withTitle: "Refresh")
      alert.addButton(withTitle: "Cancel")
      alert.addButton(withTitle: "Connect manually")
      switch alert.runModal() {
      case .alertFirstButtonReturn: return .refresh
      case .alertThirdButtonReturn: return .switchMode
      default: return .cancelled
      }
    }
  }

  @MainActor
  private static func connectManually() async throws -> ConnectionResult {
    let alert = NSAlert()
    alert.messageText = "Connect Bridge"
    alert.informativeText = "Enter your Philips Hue bridge details and application key."
    alert.addButton(withTitle: "Connect")
    alert.addButton(withTitle: "Cancel")

    let addressField = NSTextField(string: store.stringValue(for: address))
    let idField = NSTextField(string: store.stringValue(for: bridgeID))
    let pathField = NSTextField(string: store.stringValue(for: caPath))
    let keyField = NSSecureTextField(string: store.secretValue(for: key) ?? "")
    let textFields = [
      (address, addressField), (bridgeID, idField), (caPath, pathField),
    ]
    let form = NSStackView()
    form.orientation = .vertical
    form.alignment = .leading
    for (setting, field) in textFields + [(key, keyField)] {
      let label = NSTextField(labelWithString: setting.label)
      field.setAccessibilityLabel(setting.label)
      form.addArrangedSubview(label)
      form.addArrangedSubview(field)
      field.widthAnchor.constraint(equalToConstant: 320).isActive = true
    }
    let link = NSButton(
      title: "Connect automatically", target: NSApp, action: NSSelectorFromString("stopModal")
    )
    link.isBordered = false
    link.contentTintColor = .linkColor
    form.addArrangedSubview(link)
    form.setFrameSize(form.fittingSize)
    alert.accessoryView = form
    alert.layout()
    alert.window.initialFirstResponder = addressField
    NSApp.activate()
    let response = alert.runModal()
    alert.window.orderOut(nil)
    if response == .stop { return .switchMode }
    guard response == .alertFirstButtonReturn else { return .cancelled }

    try await save(
      address: addressField.stringValue, id: idField.stringValue,
      key: keyField.stringValue, path: pathField.stringValue
    )
    return .connected
  }

  @MainActor
  private static func save(address: String, id: String, key: String, path: String) async throws {
    let candidate = try bridge(address: address, id: id, key: key, path: path)
    _ = try await candidate.groups()
    try Task.checkCancellation()
    store.setSecretValue(key, for: Self.key)
    guard store.secretValue(for: Self.key) == key else {
      throw HueError.configuration("Tuna could not save the application key to the Keychain.")
    }
    store.setStringValue(address, for: Self.address)
    store.setStringValue(id, for: bridgeID)
    store.setStringValue(path, for: caPath)
  }
}

@MainActor
private final class HuePairingPrompt: NSObject, NSTableViewDataSource, NSTableViewDelegate {
  private let alert = NSAlert()
  private let table = NSTableView()
  private let connect = NSButton()
  private var bridges: [DiscoveredHueBridge] = []
  private var names: [Int: String] = [:]
  private var selection: CheckedContinuation<DiscoveredHueBridge?, Never>?
  let message = NSTextField(wrappingLabelWithString: "Looking for Hue bridges…")
  private(set) var manual = false
  private(set) var refreshRequested = false
  var cancelPairing: (() -> Void)?

  func show() {
    alert.messageText = "Connect Hue Bridge"
    let cancel = alert.addButton(withTitle: "Cancel")
    cancel.target = self
    cancel.action = #selector(cancelPressed)
    cancel.keyEquivalent = "\u{1b}"
    let scroll = NSScrollView()
    scroll.hasVerticalScroller = true
    scroll.borderType = .lineBorder
    scroll.documentView = table
    let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("bridge"))
    column.width = 405
    table.addTableColumn(column)
    table.headerView = nil
    table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    table.style = .plain
    table.usesAlternatingRowBackgroundColors = true
    table.setAccessibilityLabel("Discovered Hue bridges")
    table.dataSource = self
    table.delegate = self

    connect.title = "Continue"
    connect.bezelStyle = .rounded
    connect.target = self
    connect.action = #selector(connectPressed)
    connect.isEnabled = false
    let refresh = NSButton(title: "Refresh", target: self, action: #selector(refreshPressed))
    refresh.bezelStyle = .rounded
    let link = NSButton(title: "Connect manually", target: self, action: #selector(manualPressed))
    link.isBordered = false
    link.contentTintColor = .linkColor
    let controls = NSStackView(views: [connect, refresh])
    let content = NSStackView(views: [message, scroll, controls, link])
    content.orientation = .vertical
    content.alignment = .leading
    NSLayoutConstraint.activate([
      message.widthAnchor.constraint(equalToConstant: 420),
      scroll.widthAnchor.constraint(equalTo: message.widthAnchor),
      scroll.heightAnchor.constraint(equalToConstant: 124),
    ])
    content.setFrameSize(content.fittingSize)
    alert.accessoryView = content
    alert.layout()
    NSApp.activate()
    alert.window.makeKeyAndOrderFront(nil)
  }

  func choose(from bridges: [DiscoveredHueBridge]) async -> DiscoveredHueBridge? {
    self.bridges = bridges
    table.reloadData()
    message.stringValue = bridges.isEmpty
      ? "No Hue bridges found. Check that this Mac and the bridge are on the same network."
      : "Select a Hue bridge to connect."
    let lookup = Task {
      await withTaskGroup(of: (Int, String).self) { group in
        for (index, bridge) in bridges.enumerated() {
          group.addTask { (index, await bridge.displayName()) }
        }
        for await (index, name) in group {
          if Task.isCancelled { break }
          names[index] = name
          table.reloadData(
            forRowIndexes: IndexSet(integer: index), columnIndexes: IndexSet(integer: 0)
          )
        }
      }
    }
    defer { lookup.cancel() }
    return await withCheckedContinuation { continuation in
      selection = continuation
      if bridges.count == 1 {
        table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
      }
    }
  }

  func numberOfRows(in tableView: NSTableView) -> Int { bridges.count }

  func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
    let bridge = bridges[row]
    let name = names[row] ?? "Hue Bridge \(bridge.id.uppercased())"
    let label = NSTextField(labelWithString: "\(name) · \(bridge.internalipaddress)")
    label.lineBreakMode = .byTruncatingMiddle
    return label
  }

  func tableViewSelectionDidChange(_ notification: Notification) {
    connect.isEnabled = selection != nil && bridges.indices.contains(table.selectedRow)
  }

  func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
    selection != nil
  }

  func close() { alert.window.orderOut(nil) }

  @objc private func cancelPressed() {
    close()
    cancelPairing?()
    selection?.resume(returning: nil)
    selection = nil
  }

  @objc private func connectPressed() {
    guard let selection, bridges.indices.contains(table.selectedRow) else { return }
    self.selection = nil
    connect.isEnabled = false
    selection.resume(returning: bridges[table.selectedRow])
  }

  @objc private func manualPressed() {
    manual = true
    cancelPressed()
  }

  @objc private func refreshPressed() {
    refreshRequested = true
    cancelPressed()
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
  private var connecting = false

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
      objects = [connectCommand()]
      status = error.localizedDescription
      logger.error("Hue catalog scan failed: \(self.status, privacy: .private)")
    }
    reportScanFinished()
  }

  public func diagnosticsSnapshot() -> CatalogDiagnosticsSnapshot {
    CatalogDiagnosticsSnapshot(metrics: ["Hue": .text(status)])
  }

  private func connectCommand() -> CommandItem {
    CommandItem(
      id: "connect-bridge", title: "Connect Hue Bridge", symbol: "link",
      detail: "Philips Hue", tintColor: .systemOrange,
      headlessEligibility: .requiresInterface, executionPolicy: .dismiss
    ) { [weak self] in
      guard let self, !connecting else { return .success }
      connecting = true
      defer { connecting = false }
      do {
        if try await HueSettings.connect() { await scan() }
        return .success
      } catch {
        return .failure(error.localizedDescription)
      }
    }
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
