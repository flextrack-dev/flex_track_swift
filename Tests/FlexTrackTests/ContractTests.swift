import Foundation
import Testing

@testable import FlexTrack

@Suite("Vendored cross-SDK contract")
struct ContractTests {
  @Test("Core and Runtime fixtures remain pinned to specification 1.0")
  func fixtureEnvelope() throws {
    let root = packageRoot().appendingPathComponent("Contract")
    let core = try json(root.appendingPathComponent("core_mvp_cases.json"))
    let runtime = try json(root.appendingPathComponent("runtime_mvp_cases.json"))

    #expect(core["specVersion"] as? String == "1.0.0")
    #expect(runtime["specVersion"] as? String == "1.0.0")
    #expect((core["cases"] as? [[String: Any]])?.count == 8)
    #expect((runtime["cases"] as? [[String: Any]])?.count == 11)
  }

  @Test("Fixture case identities are unique and covered by Swift suites")
  func fixtureIdentities() throws {
    let root = packageRoot().appendingPathComponent("Contract")
    for name in ["core_mvp_cases.json", "runtime_mvp_cases.json"] {
      let document = try json(root.appendingPathComponent(name))
      let cases = try #require(document["cases"] as? [[String: Any]])
      let ids = try cases.map { try #require($0["id"] as? String) }
      #expect(Set(ids).count == ids.count)
      #expect(ids.allSatisfy { !$0.isEmpty })
    }
  }

  @Test("every Core MVP fixture executes against the Swift implementation")
  func executeCoreFixtures() throws {
    let document = try json(packageRoot().appendingPathComponent("Contract/core_mvp_cases.json"))
    let cases = try #require(document["cases"] as? [[String: Any]])
    for fixture in cases {
      try verifyCoreFixture(fixture)
    }
  }
}

private func verifyCoreFixture(_ fixture: [String: Any]) throws {
  let id = try #require(fixture["id"] as? String)
  let behavior = try #require(fixture["behavior"] as? String)
  let input = try #require(fixture["input"] as? [String: Any])
  let expected = try #require(fixture["expected"] as? [String: Any])

  switch behavior {
  case "routing", "debug":
    let eventInput = try #require(input["event"] as? [String: Any])
    let rulesInput = try #require(input["rules"] as? [[String: Any]])
    let rules = try rulesInput.map(contractRule)
    let defaultGroup = (input["defaultGroup"] as? [String]).map {
      TrackerGroup("fixture-default", trackerIDs: $0)
    }
    let engine = RoutingEngine(RoutingConfiguration(rules: rules, defaultGroup: defaultGroup))
    let result = engine.route(
      contractEvent(eventInput, requiresConsent: false), consent: .init(general: true),
      availableTrackerIDs: Set(input["availableTrackers"] as? [String] ?? []))
    let expectedTargets = expected[behavior == "debug" ? "targetTrackers" : "targets"] as? [String]
    #expect(result.targetTrackerIDs == expectedTargets, "Fixture \(id)")
    if behavior == "routing" {
      #expect(result.appliedPriorities == expected["appliedPriorities"] as? [Int], "Fixture \(id)")
    } else {
      #expect(result.targetTrackerIDs == expected["successfulTrackerIds"] as? [String], "Fixture \(id)")
    }
  case "consent":
    let eventInput = try #require(input["event"] as? [String: Any])
    let rule = try contractRule(try #require(input["rule"] as? [String: Any]))
    let result = RoutingEngine(RoutingConfiguration(rules: [rule])).route(
      contractEvent(eventInput),
      consent: .init(
        general: input["generalConsent"] as? Bool ?? false,
        pii: input["piiConsent"] as? Bool ?? false),
      availableTrackerIDs: Set(rule.targetGroup.trackerIDs))
    #expect(result.targetTrackerIDs == expected["targets"] as? [String], "Fixture \(id)")
    #expect(result.skippedRules.map(\.reason) == expected["skipReasons"] as? [String], "Fixture \(id)")
  case "sampling":
    let identity = try #require(input["identity"] as? String)
    let rate = try #require(input["sampleRate"] as? Double)
    #expect(Int(DeterministicSampler.stableHash(identity)) == expected["hash"] as? Int, "Fixture \(id)")
    #expect(
      DeterministicSampler.includes(event: FlexEvent(name: "fixture", userID: identity), rate: rate)
        == expected["accepted"] as? Bool,
      "Fixture \(id)")
  case "enrichment":
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let timestampText = try #require(input["timestamp"] as? String)
    let timestamp = try #require(formatter.date(from: timestampText))
    let event = FlexEvent(
      id: try #require(input["eventId"] as? String), timestamp: timestamp,
      name: try #require(input["name"] as? String),
      properties: contractProperties(input["properties"] as? [String: Any] ?? [:]),
      requiresConsent: false)
    let enriched = event.enriched(
      with: contractProperties(input["extraProperties"] as? [String: Any] ?? [:]))
    #expect(enriched.id == expected["eventId"] as? String, "Fixture \(id)")
    #expect(enriched.timestamp == formatter.date(from: expected["timestamp"] as? String ?? ""), "Fixture \(id)")
    #expect(enriched.properties == contractProperties(expected["properties"] as? [String: Any] ?? [:]), "Fixture \(id)")
  default:
    Issue.record("Unsupported Core fixture behavior \(behavior)")
  }
}

private func contractRule(_ value: [String: Any]) throws -> RoutingRule {
  let targets = try #require(value["targets"] as? [String])
  return RoutingRule(
    priority: value["priority"] as? Int ?? 0,
    targetGroup: TrackerGroup("fixture-\(targets.joined())", trackerIDs: targets),
    nameContains: value["nameContains"] as? String,
    category: value["category"] as? String,
    isDefault: value["default"] as? Bool ?? false,
    requireConsent: value["requireConsent"] as? Bool ?? false,
    requirePIIConsent: value["requirePIIConsent"] as? Bool ?? false)
}

private func contractEvent(
  _ value: [String: Any], requiresConsent: Bool? = nil
) -> FlexEvent {
  FlexEvent(
    name: value["name"] as? String ?? "fixture",
    category: value["category"] as? String,
    containsPII: value["containsPII"] as? Bool ?? false,
    requiresConsent: requiresConsent ?? value["requiresConsent"] as? Bool ?? true)
}

private func contractProperties(_ values: [String: Any]) -> [String: JSONValue] {
  values.mapValues { value in
    switch value {
    case let value as Bool: .bool(value)
    case let value as NSNumber: .number(value.doubleValue)
    case let value as String: .string(value)
    default: .null
    }
  }
}

private func packageRoot() -> URL {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
}

private func json(_ url: URL) throws -> [String: Any] {
  try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
}
