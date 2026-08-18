import Foundation
import Testing

@testable import FlexTrack

@Suite("Core contract")
struct CoreTests {
  @Test("event identity and timestamp survive enrichment")
  func enrichmentIdentity() {
    let timestamp = Date(timeIntervalSince1970: 1_777_000_000)
    let event = FlexEvent(
      id: "event-1",
      timestamp: timestamp,
      name: "purchase",
      properties: ["plan": .string("free")],
      requiresConsent: false
    )
    let enriched = event.enriched(with: ["plan": .string("pro"), "surface": .string("ios")])

    #expect(enriched.id == "event-1")
    #expect(enriched.timestamp == timestamp)
    #expect(enriched.properties["plan"] == .string("pro"))
    #expect(enriched.properties["surface"] == .string("ios"))
  }

  @Test("highest matching priority wins and same tier merges in order")
  func priorityRouting() {
    let engine = RoutingEngine(
      RoutingConfiguration(rules: [
        RoutingRule(
          priority: 5, targetGroup: TrackerGroup("a", trackerIDs: ["analytics"]),
          nameContains: "purchase", requireConsent: false),
        RoutingRule(
          priority: 5, targetGroup: TrackerGroup("b", trackerIDs: ["archive", "analytics"]),
          nameContains: "purchase", requireConsent: false),
        RoutingRule(
          priority: 0, targetGroup: TrackerGroup("fallback", trackerIDs: ["fallback"]),
          isDefault: true, requireConsent: false),
      ]))

    let result = engine.route(
      FlexEvent(name: "purchase", requiresConsent: false),
      consent: ConsentState(),
      availableTrackerIDs: ["analytics", "archive", "fallback"]
    )

    #expect(result.targetTrackerIDs == ["analytics", "archive"])
    #expect(result.appliedPriorities == [5, 5])
  }

  @Test("privacy-safe consent defaults reject protected events")
  func consentDefaults() {
    let engine = RoutingEngine(
      RoutingConfiguration(rules: [
        RoutingRule(
          id: "protected", targetGroup: TrackerGroup("all", trackerIDs: ["analytics"]),
          nameContains: "profile")
      ]))
    let result = engine.route(
      FlexEvent(name: "profile_update", containsPII: true),
      consent: ConsentState(),
      availableTrackerIDs: ["analytics"]
    )

    #expect(result.targetTrackerIDs.isEmpty)
    #expect(result.skippedRules.first?.reason == "Consent requirements not met")
  }

  @Test("sampling is deterministic for the same stable key")
  func deterministicSampling() {
    let event = FlexEvent(name: "purchase", userID: "user-42")
    let values = (0..<100).map { _ in DeterministicSampler.includes(event: event, rate: 0.35) }
    #expect(Set(values).count == 1)
  }
}
