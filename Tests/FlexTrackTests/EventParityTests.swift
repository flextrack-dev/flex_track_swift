import Foundation
import Testing

@testable import FlexTrack

@Suite("Event parity")
struct EventParityTests {
  @Test("JSON values round-trip without losing nested types")
  func jsonRoundTrip() throws {
    let value: [String: JSONValue] = [
      "null": .null,
      "bool": .bool(true),
      "number": .number(12.5),
      "string": .string("hello"),
      "array": .array([.number(1), .string("two")]),
      "object": .object(["nested": .bool(false)]),
    ]

    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode([String: JSONValue].self, from: data)

    #expect(decoded == value)
  }

  @Test("event round-trip preserves its complete delivery identity")
  func eventRoundTrip() throws {
    let event = FlexEvent(
      id: "event-42",
      timestamp: Date(timeIntervalSince1970: 1_777_000_000),
      name: "purchase",
      properties: ["plan": .string("pro")],
      category: "business",
      containsPII: true,
      requiresConsent: true,
      isEssential: false,
      userID: "user-1",
      sessionID: "session-1"
    )

    let decoded = try JSONDecoder().decode(FlexEvent.self, from: JSONEncoder().encode(event))

    #expect(decoded == event)
  }

  @Test("enrichment overrides collisions and retains all event metadata")
  func enrichmentMetadata() {
    let timestamp = Date(timeIntervalSince1970: 1_777_000_000)
    let event = FlexEvent(
      id: "event-1", timestamp: timestamp, name: "profile",
      properties: ["plan": .string("free")], category: "account", containsPII: true,
      requiresConsent: true, isEssential: true, userID: "user", sessionID: "session")

    let enriched = event.enriched(with: ["plan": .string("pro"), "route": .string("/pay")])

    #expect(enriched.id == event.id)
    #expect(enriched.timestamp == timestamp)
    #expect(enriched.name == "profile")
    #expect(enriched.category == "account")
    #expect(enriched.containsPII)
    #expect(enriched.requiresConsent)
    #expect(enriched.isEssential)
    #expect(enriched.userID == "user")
    #expect(enriched.sessionID == "session")
    #expect(enriched.properties == ["plan": .string("pro"), "route": .string("/pay")])
  }
}
