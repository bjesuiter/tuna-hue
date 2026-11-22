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

@MainActor
private enum HuePairing {
  static func connect() async throws -> Bool {
    var manual = false
    while true {
      let result = try await (manual ? connectManually() : connectAutomatically())
      switch result {
      case .connected(let name):
        showConnectionConfirmation(for: name)
        return true
      case .cancelled: return false
      case .switchMode: manual.toggle()
      case .refresh: break
      }
    }
  }

  private enum ConnectionResult {
    case connected(String)
    case cancelled, switchMode, refresh
  }

  private static func connectAutomatically() async throws -> ConnectionResult {
    let prompt = HuePairingPrompt()
    prompt.show()
    defer {
      prompt.cancelPairing = nil
      prompt.close()
    }
    let pairing = Task { () throws -> String? in
      let connected = Set(try HueConnections.records().keys)
      let bridges = try await DiscoveredHueBridge.discover().filter {
        !connected.contains($0.id.lowercased())
      }
      try Task.checkCancellation()
      let bridge = await prompt.choose(from: bridges)
      try Task.checkCancellation()
      guard let bridge else {
        return nil
      }
      let id = bridge.id.lowercased()
      try HueConnections.requireNew(id)
      let address = bridge.internalipaddress
      prompt.message.stringValue = "Press the physical link button on your Hue Bridge."
      let client = try HueBridge(address: address, id: id, caPEM: hueRootCertificates)
      let key = try await client.pair()
      try Task.checkCancellation()
      prompt.message.stringValue = "Verifying the bridge connection…"
      return try await HueConnections.add(address: address, id: id, key: key, path: "")
    }
    prompt.cancelPairing = { pairing.cancel() }
    do {
      let name = try await pairing.value
      if prompt.refreshRequested { return .refresh }
      return name.map(ConnectionResult.connected) ?? .cancelled
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

  private static func connectManually() async throws -> ConnectionResult {
    let alert = NSAlert()
    alert.messageText = "Connect Bridge"
    alert.informativeText = "Enter your Philips Hue bridge details and application key."
    alert.addButton(withTitle: "Connect")
    alert.addButton(withTitle: "Cancel")

    let addressField = NSTextField(string: "")
    let idField = NSTextField(string: "")
    let pathField = NSTextField(string: "")
    let keyField = NSSecureTextField(string: "")
    let fields: [(String, NSTextField)] = [
      ("Bridge address", addressField), ("Bridge ID", idField),
      ("Hue root CA PEM path (optional)", pathField), ("Application key", keyField),
    ]
    let form = NSStackView()
    form.orientation = .vertical
    form.alignment = .leading
    for (title, field) in fields {
      let label = NSTextField(labelWithString: title)
      field.setAccessibilityLabel(title)
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

    let name = try await HueConnections.add(
      address: addressField.stringValue, id: idField.stringValue,
      key: keyField.stringValue, path: pathField.stringValue
    )
    return .connected(name)
  }

  private static func showConnectionConfirmation(for name: String) {
    let alert = NSAlert()
    alert.messageText = "Successfully connected to Hue bridge “\(name)”"
    alert.addButton(withTitle: "Done")
    alert.runModal()
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
    alert.messageText = "Add Hue Bridge"
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
      ? "No new Hue bridges found. Check that this Mac and the bridge are on the same network."
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
    var items: [CatalogItem] = []
    do {
      let records = try HueConnections.records()
      let groupsByBridge = await withTaskGroup(
        of: (String, Result<[HueGroup], Error>).self
      ) { tasks in
        for id in records.keys {
          tasks.addTask {
            do {
              let groups = try await HueConnections.use(id) { bridge in
                async let name = try? bridge.name()
                let groups = try await bridge.groups()
                return (groups, await name)
              }
              if let name = groups.1, let generation = records[id]?.generation {
                try? await HueConnections.updateName(name, for: id, generation: generation)
              }
              return (id, .success(groups.0))
            } catch {
              return (id, .failure(error))
            }
          }
        }
        var results: [String: Result<[HueGroup], Error>] = [:]
        for await (id, result) in tasks { results[id] = result }
        return results
      }
      guard scanID == currentScan, !Task.isCancelled else { return }
      let current = try HueConnections.records()
      if !current.isEmpty {
        items.append(bridgeCommand(manage: true))
      }
      var groupCount = 0
      var failed = 0
      for id in current.keys.sorted() {
        guard let record = current[id], records[id]?.generation == record.generation,
              let result = groupsByBridge[id] else { continue }
        switch result {
        case .success(let groups):
          groupCount += groups.count
          let bridgeLabel = Self.label(for: record, among: current)
          items += groups.map { HueGroupItem(group: $0, bridge: record, bridgeLabel: bridgeLabel) }
        case .failure(let error):
          failed += 1
          logger.error("Hue scan for \(record.name, privacy: .private) failed: \(error.localizedDescription, privacy: .private)")
        }
      }
      items.append(bridgeCommand(manage: false, first: current.isEmpty))
      status = current.isEmpty ? "No Hue bridges connected"
        : "Loaded \(groupCount) Hue groups from \(current.count - failed) of \(current.count) bridges"
    } catch {
      guard scanID == currentScan, !Task.isCancelled else { return }
      status = error.localizedDescription
      logger.error("Hue catalog scan failed: \(self.status, privacy: .private)")
    }
    objects = items
    reportScanFinished()
  }

  public func diagnosticsSnapshot() -> CatalogDiagnosticsSnapshot {
    CatalogDiagnosticsSnapshot(metrics: ["Hue": .text(status)])
  }

  private static func label(for record: HueConnection, among records: [String: HueConnection]) -> String {
    let duplicate = records.values.contains {
      $0.id != record.id && $0.name.localizedCaseInsensitiveCompare(record.name) == .orderedSame
    }
    return duplicate ? "\(record.name) (\(record.id.uppercased()))" : record.name
  }

  private func bridgeCommand(manage: Bool, first: Bool = false) -> CatalogItem {
    let title = manage ? "Manage Hue Bridges" : (first ? "Connect First Hue Bridge" : "Add Hue Bridge")
    let command = CommandItem(
      id: manage ? "manage-bridges" : "connect-bridge",
      title: title,
      symbol: manage ? "gearshape" : "link",
      detail: "Philips Hue", tintColor: .systemOrange,
      headlessEligibility: .requiresInterface, executionPolicy: .dismiss
    ) { [weak self] in
      guard let self, !connecting else { return .success }
      connecting = true
      defer { connecting = false }
      do {
        let changed = try await (manage ? Self.manageBridges() : HuePairing.connect())
        if changed { await scan() }
        return .success
      } catch {
        return .failure(error.localizedDescription)
      }
    }
    return manage || first ? command : AddHueBridgeItem(command: command)
  }

  private static func manageBridges() throws -> Bool {
    let records = try HueConnections.records()
    let sorted = records.values.sorted {
      let order = $0.name.localizedStandardCompare($1.name)
      return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
    }
    NSApp.activate()
    let alert = NSAlert()
    alert.messageText = "Manage Hue Bridges"
    guard !sorted.isEmpty else {
      alert.informativeText = "No Hue bridges are connected. Use Connect First Hue Bridge to connect one."
      alert.addButton(withTitle: "Done")
      alert.runModal()
      return false
    }

    alert.informativeText = "Choose a connected bridge to disconnect."
    alert.addButton(withTitle: "Done")
    alert.addButton(withTitle: "Disconnect…")
    let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
    picker.setAccessibilityLabel("Connected Hue bridges")
    picker.addItems(withTitles: sorted.map {
      "\(label(for: $0, among: records)) · \($0.address)"
    })
    alert.accessoryView = picker
    guard alert.runModal() == .alertSecondButtonReturn,
          sorted.indices.contains(picker.indexOfSelectedItem) else { return false }
    alert.window.orderOut(nil)

    let record = sorted[picker.indexOfSelectedItem]
    let confirm = NSAlert()
    confirm.alertStyle = .warning
    confirm.messageText = "Disconnect “\(label(for: record, among: records))”?"
    confirm.informativeText = "Tuna will remove this bridge and its saved application key from this Mac."
    confirm.addButton(withTitle: "Cancel")
    confirm.addButton(withTitle: "Disconnect").hasDestructiveAction = true
    guard confirm.runModal() == .alertSecondButtonReturn else { return false }
    try HueConnections.disconnect(record.id)
    return true
  }
}

private final class AddHueBridgeItem: CatalogEntity, Runnable, @unchecked Sendable {
  private let command: CommandItem

  init(command: CommandItem) {
    self.command = command
    super.init(id: command.id, title: command.title, path: nil)
    type = command.type
    typeID = command.typeID
  }

  override var detail: String? { command.detail }
  override var searchKeys: [String] { super.searchKeys + ["Connect Hue Bridge"] }
  var headlessEligibility: CommandHeadlessEligibility { command.headlessEligibility }
  var executionPolicy: CommandExecutionPolicy { command.executionPolicy }

  func run() async -> ActionResult { await command.run() }

  override func preview(maxDimension: CGFloat) -> CatalogItemPreview {
    command.preview(maxDimension: maxDimension)
  }

  override func placeholderPreview(maxDimension: CGFloat) -> CatalogItemPreview {
    command.placeholderPreview(maxDimension: maxDimension)
  }
}

private final class HueGroupItem: CatalogEntity, @unchecked Sendable {
  let group: HueGroup
  let bridgeID: String

  private let bridgeName: String
  private let bridgeLabel: String

  init(group: HueGroup, bridge: HueConnection, bridgeLabel: String) {
    self.group = group
    bridgeID = bridge.id
    bridgeName = bridge.name
    self.bridgeLabel = bridgeLabel
    super.init(id: "\(bridge.id)/\(group.kind.rawValue)/\(group.id)", title: group.name, path: nil)
    typeID = .hueGroup
  }

  override var detail: String? { "\(group.kind.label) · \(bridgeLabel)" }

  override var searchKeys: [String] {
    super.searchKeys + ["Hue", "Hue \(group.name)", "\(bridgeName) \(group.name)"]
  }

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
        try await HueConnections.use(item.bridgeID) { bridge in
          try await bridge.setPower(on, lightID: item.group.lightID)
        }
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
