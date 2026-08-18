import Testing

@testable import FlexTrack

@Suite("Routing parity")
struct RoutingParityTests {
  private let analytics = TrackerGroup("analytics", trackerIDs: ["analytics"])

  @Test("name and category conditions must both match")
  func compoundConditions() {
    let engine = makeEngine([
      RoutingRule(
        targetGroup: analytics, nameContains: "purchase", category: "business",
        requireConsent: false)
    ])

    #expect(route(engine, name: "purchase", category: "debug").targetTrackerIDs.isEmpty)
    #expect(route(engine, name: "view", category: "business").targetTrackerIDs.isEmpty)
    #expect(route(engine, name: "purchase", category: "business").targetTrackerIDs == ["analytics"])
  }

  @Test("default rules are ignored when a non-default rule matches")
  func explicitBeforeDefault() {
    let engine = makeEngine([
      RoutingRule(
        priority: 0, targetGroup: TrackerGroup("fallback", trackerIDs: ["fallback"]),
        isDefault: true, requireConsent: false),
      RoutingRule(
        priority: -5, targetGroup: analytics, nameContains: "purchase", requireConsent: false),
    ])

    let result = engine.route(
      FlexEvent(name: "purchase", requiresConsent: false), consent: .init(),
      availableTrackerIDs: ["analytics", "fallback"])

    #expect(result.targetTrackerIDs == ["analytics"])
    #expect(result.appliedPriorities == [-5])
  }

  @Test("configured default group handles an unmatched event")
  func defaultGroupFallback() {
    let engine = RoutingEngine(
      RoutingConfiguration(
        rules: [RoutingRule(targetGroup: analytics, nameContains: "purchase")],
        defaultGroup: TrackerGroup("fallback", trackerIDs: ["archive"])))

    let result = engine.route(
      FlexEvent(name: "view", requiresConsent: false), consent: .init(),
      availableTrackerIDs: ["archive"])

    #expect(result.targetTrackerIDs == ["archive"])
    #expect(result.appliedPriorities == [0])
  }

  @Test("general and PII consent failures use the shared contract reason")
  func consentReasons() {
    let rule = RoutingRule(id: "protected", targetGroup: analytics, nameContains: "profile")
    let engine = makeEngine([rule])

    let general = engine.route(
      FlexEvent(name: "profile", requiresConsent: true), consent: .init(),
      availableTrackerIDs: ["analytics"])
    let pii = engine.route(
      FlexEvent(name: "profile", containsPII: true, requiresConsent: false),
      consent: .init(general: true, pii: false), availableTrackerIDs: ["analytics"])

    #expect(general.skippedRules == [.init(ruleID: "protected", reason: "Consent requirements not met")])
    #expect(pii.skippedRules == [.init(ruleID: "protected", reason: "Consent requirements not met")])
  }

  @Test("disabling consent checks routes protected events")
  func disabledConsentChecks() {
    let engine = RoutingEngine(
      RoutingConfiguration(
        rules: [RoutingRule(targetGroup: analytics, nameContains: "profile")],
        consentCheckingEnabled: false))

    let result = engine.route(
      FlexEvent(name: "profile", containsPII: true), consent: .init(),
      availableTrackerIDs: ["analytics"])

    #expect(result.targetTrackerIDs == ["analytics"])
  }

  @Test("essential events bypass consent and zero-percent sampling")
  func essentialBypass() {
    let engine = makeEngine([
      RoutingRule(targetGroup: analytics, nameContains: "crash", samplingRate: 0)
    ])

    let result = engine.route(
      FlexEvent(name: "crash", containsPII: true, isEssential: true), consent: .init(),
      availableTrackerIDs: ["analytics"])

    #expect(result.targetTrackerIDs == ["analytics"])
  }

  @Test("sampling boundaries and disabled sampling are exact")
  func samplingBoundaries() {
    let rejected = makeEngine([
      RoutingRule(
        targetGroup: analytics, nameContains: "purchase", requireConsent: false,
        samplingRate: 0)
    ])
    let disabled = RoutingEngine(
      RoutingConfiguration(rules: rejected.configuration.rules, samplingEnabled: false))

    #expect(route(rejected).targetTrackerIDs.isEmpty)
    #expect(route(rejected).skippedRules.first?.reason == "Event was sampled out")
    #expect(route(disabled).targetTrackerIDs == ["analytics"])
  }

  @Test("duplicate and unavailable tracker IDs are handled deterministically")
  func trackerAvailability() {
    let group = TrackerGroup("mixed", trackerIDs: ["analytics", "analytics", "missing"])
    let engine = makeEngine([
      RoutingRule(targetGroup: group, nameContains: "purchase", requireConsent: false)
    ])

    let partial = route(engine)
    let unavailable = engine.route(
      FlexEvent(name: "purchase", requiresConsent: false), consent: .init(),
      availableTrackerIDs: [])

    #expect(partial.targetTrackerIDs == ["analytics"])
    #expect(partial.warnings.isEmpty)
    #expect(unavailable.targetTrackerIDs.isEmpty)
    #expect(unavailable.warnings == ["Rule resolved to no available trackers"])
  }

  @Test("debug explains every failed condition")
  func debugReasons() throws {
    let rule = RoutingRule(
      id: "diagnostic", targetGroup: analytics, nameRegex: "^logout$",
      category: "security", propertyName: "reason", requireConsent: false)
    let engine = makeEngine([rule])

    let decision = try #require(engine.debug(
      FlexEvent(name: "purchase", category: "business", requiresConsent: false),
      availableTrackerIDs: ["analytics"]
    ).decisions.first)

    #expect(decision.reason?.contains("does not match /^logout$/") == true)
    #expect(decision.reason?.contains("Category mismatch") == true)
    #expect(decision.reason?.contains("Missing property 'reason'") == true)
  }

  @Test("engine exposes configuration validation")
  func validation() {
    let engine = makeEngine([
      RoutingRule(id: "duplicate", targetGroup: analytics, isDefault: true),
      RoutingRule(id: "duplicate", targetGroup: analytics),
    ])
    #expect(engine.validateConfiguration().first?.contains("Duplicate rule IDs") == true)
  }

  private func makeEngine(_ rules: [RoutingRule]) -> RoutingEngine {
    RoutingEngine(RoutingConfiguration(rules: rules))
  }

  private func route(
    _ engine: RoutingEngine, name: String = "purchase", category: String? = nil
  ) -> RoutingResult {
    engine.route(
      FlexEvent(name: name, category: category, requiresConsent: false), consent: .init(),
      availableTrackerIDs: ["analytics"])
  }
}
