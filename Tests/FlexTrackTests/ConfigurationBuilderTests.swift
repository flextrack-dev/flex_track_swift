import Testing

@testable import FlexTrack

@Suite("Flutter-parity configuration builder")
struct ConfigurationBuilderTests {
  @Test("automatic default is added with the Flutter priority")
  func automaticDefault() {
    let config = RoutingBuilder().build()
    #expect(config.rules.count == 1)
    #expect(config.rules[0].id == "auto-default")
    #expect(config.rules[0].priority == -1000)
    #expect(config.rules[0].targetGroup == .all)
  }

  @Test("explicit default prevents automatic fallback")
  func explicitDefault() throws {
    let config = try RoutingBuilder().routeDefault { try $0.toTracker("archive") }.build()
    #expect(config.rules.count == 1)
    #expect(config.rules[0].targetGroup.trackerIDs == ["archive"])
  }

  @Test("named groups can be targets and defaults")
  func namedGroups() throws {
    let builder = RoutingBuilder()
    try builder.defineGroup("product", trackerIDs: ["analytics", "archive"])
      .setDefaultGroup(named: "product")
      .routeNamed("purchase") { try $0.toGroup(named: "product") }
    let config = builder.build()
    #expect(config.defaultGroup?.trackerIDs == ["analytics", "archive"])
    #expect(config.rules[0].targetGroup.id == "product")
  }

  @Test("predefined groups and categories match Flutter")
  func predefinedValues() {
    let builder = RoutingBuilder()
    #expect(builder.getAllGroups() == [.all, .development])
    #expect(builder.getAllCategories().count == 7)
    #expect(builder.getCategory(named: "security") == "security")
  }

  @Test("priority sorting is descending and stable")
  func stablePriority() throws {
    let config = try RoutingBuilder()
      .routeNamed("low") { try $0.toAll().id("low").priority(-1) }
      .routeNamed("first") { try $0.toAll().id("first").priority(10) }
      .routeNamed("second") { try $0.toAll().id("second").priority(10) }
      .build()
    #expect(config.rules.compactMap(\.id) == ["first", "second", "low", "auto-default"])
  }

  @Test("global switches are retained")
  func switches() {
    let config = RoutingBuilder().sampling(false).consentChecking(false).debugMode(true).build()
    #expect(!config.samplingEnabled)
    #expect(!config.consentCheckingEnabled)
    #expect(config.isDebugMode)
  }

  @Test("substring regex and exact-name routes execute")
  func nameConditions() throws {
    let config = try RoutingBuilder()
      .routeNamed("purchase") { $0.toAll() }
      .routeMatching("^cart_[0-9]+$") { $0.toAll() }
      .routeExact("logout") { $0.toAll() }
      .build()
    #expect(config.rules[0].nameContains == "purchase")
    #expect(config.rules[1].nameRegex == "^cart_[0-9]+$")
    #expect(route(config, event: .init(name: "cart_42", requiresConsent: false)))
    #expect(route(config, event: .init(name: "logout", requiresConsent: false)))
    #expect(result(config, event: .init(name: "logout_now", requiresConsent: false))
      .appliedPriorities == [-1000])
  }

  @Test("custom categories resolve and route")
  func categories() throws {
    let builder = RoutingBuilder()
    try builder.defineCategory("commerce")
      .routeCategory("commerce") { $0.toAll() }
    #expect(builder.getAllCategories().count == 8)
    #expect(route(builder.build(), event: .init(
      name: "sale", category: "commerce", requiresConsent: false)))
  }

  @Test("property matching checks key and optional value")
  func propertyCondition() throws {
    let config = try RoutingBuilder()
      .routeWithProperty("plan", value: .string("pro")) { $0.toAll() }
      .build()
    #expect(route(config, event: .init(
      name: "upgrade", properties: ["plan": .string("pro")], requiresConsent: false)))
    #expect(result(config, event: .init(
      name: "upgrade", properties: ["plan": .string("free")], requiresConsent: false))
      .appliedPriorities == [-1000])
  }

  @Test("PII high-volume and essential conditions execute")
  func metadataConditions() throws {
    let pii = try RoutingBuilder().routePII { $0.toAll().skipConsent() }.build()
    let volume = try RoutingBuilder().routeHighVolume { $0.toAll().skipConsent() }.build()
    let essential = try RoutingBuilder().routeEssential { $0.toAll().skipConsent() }.build()
    #expect(route(pii, event: .init(name: "profile", containsPII: true, requiresConsent: false)))
    #expect(route(volume, event: .init(name: "scroll", requiresConsent: false, isHighVolume: true)))
    #expect(route(essential, event: .init(name: "crash", requiresConsent: false, isEssential: true)))
  }

  @Test("sampling shortcuts match Flutter percentages")
  func samplingShortcuts() throws {
    let config = try RoutingBuilder()
      .routeNamed("heavy") { $0.toAll().heavySampling() }
      .routeNamed("light") { $0.toAll().lightSampling() }
      .routeNamed("medium") { $0.toAll().mediumSampling() }
      .routeNamed("none") { $0.toAll().noSampling() }
      .build()
    #expect(config.rules.prefix(4).map(\.samplingRate) == [0.01, 0.1, 0.5, 1])
  }

  @Test("environment modifiers are mutually exclusive by last call")
  func environments() throws {
    let rule = try RoutingBuilder().routeNamed("debug") {
      $0.toAll().onlyInDebug().onlyInProduction()
    }.build().rules[0]
    #expect(!rule.debugOnly)
    #expect(rule.productionOnly)
  }

  @Test("essential shortcut skips consent sampling and raises priority")
  func essentialShortcut() throws {
    let rule = try RoutingBuilder().routeNamed("crash") {
      $0.toAll().essential()
    }.build().rules[0]
    #expect(!rule.requireConsent)
    #expect(rule.samplingRate == 1)
    #expect(rule.priority == 10)
  }

  @Test("smart defaults mirror Flutter baseline")
  func smartDefaults() throws {
    let config = try RoutingBuilder().applySmartDefaults().build()
    #expect(config.rules.map(\.priority) == [8, 5, 0])
    #expect(config.rules.last?.isDefault == true)
  }

  @Test("bulk add clear and remove operations are deterministic")
  func bulkOperations() throws {
    let manual = RoutingRule(id: "manual", targetGroup: .all)
    let builder = RoutingBuilder().addRules([manual])
    #expect(builder.build().rules.contains { $0.id == "manual" })
    builder.removeRules { $0.id == "missing" }.clearRules()
    #expect(builder.build().rules.map(\.id) == ["auto-default"])
  }

  @Test("validation and debug metadata expose configuration mistakes")
  func validationAndDebug() throws {
    let builder = RoutingBuilder()
    try builder.defineGroup("unused", trackerIDs: ["archive"])
      .routeNamed("one") { try $0.toAll().id("duplicate") }
      .routeNamed("two") { try $0.toAll().id("duplicate") }
    #expect(builder.validate().contains { $0.contains("Duplicate rule IDs") })
    #expect(builder.validate().contains { $0.contains("Unreferenced custom groups") })
    #expect(builder.debugInfo()["rulesCount"] as? Int == 2)
  }

  @Test("invalid names targets references sampling and metadata fail")
  func invalidInputs() {
    #expect(throws: FlexTrackConfigurationError.empty("group name")) {
      try RoutingBuilder().defineGroup("", trackerIDs: ["analytics"])
    }
    #expect(throws: FlexTrackConfigurationError.unknownGroup("missing")) {
      try RoutingBuilder().setDefaultGroup(named: "missing")
    }
    #expect(throws: FlexTrackConfigurationError.missingTarget) {
      try RoutingBuilder().routeNamed("event") { _ in }
    }
    #expect(throws: FlexTrackConfigurationError.invalidSamplingRate(1.1)) {
      try RoutingBuilder().routeNamed("event") { try $0.toAll().sample(1.1) }
    }
  }

  @Test("client builder wires tracker transformer routing and lifecycle")
  func clientBuilder() async throws {
    let tracker = BuilderTracker(id: "analytics")
    let client = try await FlexTrackBuilder()
      .tracker(tracker)
      .transformer { $0.enriched(with: ["surface": .string("builder")]) }
      .routing { try $0.routeDefault { try $0.toTracker("analytics").skipConsent() } }
      .build()
    let result = try await client.track(.init(name: "purchase", requiresConsent: false))
    #expect(result.successfulTrackerIDs == ["analytics"])
    #expect(await tracker.lastEvent?.properties["surface"] == .string("builder"))
    #expect(await tracker.starts == 1)
  }

  @Test("client builder requires a tracker and supports unstarted clients")
  func clientBuilderValidation() async throws {
    await #expect(throws: FlexTrackConfigurationError.missingTracker) {
      try await FlexTrackBuilder().build()
    }
    let tracker = BuilderTracker(id: "analytics")
    let client = try await FlexTrackBuilder()
      .tracker(tracker)
      .routing { try $0.routeDefault { try $0.toTracker("analytics") } }
      .build(autoStart: false)
    await #expect(throws: FlexTrackError.clientNotStarted) {
      try await client.track(.init(name: "purchase"))
    }
  }

  @Test("tracking context wires consent and dynamic enrichment")
  func contextIntegration() async throws {
    let consent = ConsentManager(); consent.setConsents(general: true, version: "1")
    final class ContextBox: @unchecked Sendable {
      var value: TrackingContext
      init(_ value: TrackingContext) { self.value = value }
    }
    let box = ContextBox(TrackingContext(userID: "first", sessionID: "session", consentManager: consent))
    let tracker = BuilderTracker(id: "analytics")
    let client = try await FlexTrackBuilder()
      .tracker(tracker)
      .trackingContext { box.value }
      .routing { try $0.routeDefault { try $0.toTracker("analytics") } }
      .build()
    _ = try await client.track(.init(name: "first"))
    box.value = box.value.withUserID("second")
    _ = try await client.track(.init(name: "second"))
    #expect(await tracker.events.map { $0.properties["user_id"] } == [.string("first"), .string("second")])
  }

  private func route(_ configuration: RoutingConfiguration, event: FlexEvent) -> Bool {
    !result(configuration, event: event).targetTrackerIDs.isEmpty
  }

  private func result(_ configuration: RoutingConfiguration, event: FlexEvent) -> RoutingResult {
    RoutingEngine(configuration).route(
      event, consent: .init(general: true, pii: true), availableTrackerIDs: ["analytics"]
    )
  }
}

private actor BuilderTracker: Tracker {
  nonisolated let id: String
  private(set) var starts = 0
  private(set) var lastEvent: FlexEvent?
  private(set) var events: [FlexEvent] = []
  init(id: String) { self.id = id }
  func start() { starts += 1 }
  func track(_ event: FlexEvent) { lastEvent = event; events.append(event) }
}
