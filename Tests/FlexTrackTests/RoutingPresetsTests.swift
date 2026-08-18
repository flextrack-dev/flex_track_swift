import Testing

@testable import FlexTrack

@Suite("Flutter-parity routing presets")
struct RoutingPresetsTests {
  @Test("smart defaults contain all eight public Flutter rules")
  func smartDefaults() throws {
    let rules = try rules(SmartDefaults.apply)
    #expect(rules.count == 8)
    #expect(rules.map(\.priority) == [20, 15, 12, 10, 8, 7, 5, 0])
    #expect(rules.last?.isDefault == true)
  }

  @Test("smart security and essential rules bypass consent and sampling")
  func smartBypass() throws {
    let values = try rules(SmartDefaults.apply)
    let security = try #require(values.first { $0.category == "security" })
    let essential = try #require(values.first { $0.isEssential == true })
    #expect(!security.requireConsent && security.samplingRate == 1)
    #expect(!essential.requireConsent && essential.samplingRate == 1)
  }

  @Test("performance-focused smart defaults add frequency rules")
  func smartPerformance() throws {
    let values = try rules(SmartDefaults.applyPerformanceFocused)
    #expect(values.count == 10)
    #expect(values.first { $0.propertyName == "high_frequency" }?.samplingRate == 0.01)
    #expect(values.first { $0.propertyName == "batchable" }?.samplingRate == 0.5)
  }

  @Test("privacy-focused smart defaults add consent categories")
  func smartPrivacy() throws {
    let values = try rules(SmartDefaults.applyPrivacyFocused)
    #expect(values.count == 10)
    #expect(values.first { $0.category == "user" }?.requireConsent == true)
    #expect(values.first { $0.category == "marketing" }?.requireConsent == true)
  }

  @Test("development smart defaults prepend three debug regexes")
  func smartDevelopment() throws {
    let values = try rules(SmartDefaults.applyDevelopmentFriendly)
    #expect(values.count == 11)
    #expect(values.filter { $0.nameRegex != nil }.map(\.priority) == [15, 14, 13])
    #expect(values.filter { $0.nameRegex != nil }.allSatisfy { $0.debugOnly })
  }

  @Test("GDPR defaults match Flutter rule count and priority bounds")
  func gdpr() throws {
    let values = try rules { try PrivacyDefaults.apply(to: $0) }
    #expect(values.count == 14)
    #expect(values.first?.priority == 25)
    #expect(values.last?.priority == 0)
    #expect(values.last?.samplingRate == 0.5)
  }

  @Test("GDPR compliant destinations use their named group")
  func gdprGroup() throws {
    let builder = RoutingBuilder()
    try PrivacyDefaults.apply(to: builder, compliantTrackerIDs: ["safe-a", "safe-b"])
    let config = builder.build()
    #expect(config.customGroups["gdpr_compliant"]?.trackerIDs == ["safe-a", "safe-b"])
    #expect(config.rules.first { $0.containsPII == true }?.targetGroup.id == "gdpr_compliant")
    #expect(config.rules.first { $0.propertyName == "email" }?.targetGroup.id == "gdpr_compliant")
  }

  @Test("strict GDPR adds identity session and behavioral rules")
  func strictGDPR() throws {
    let values = try rules { try PrivacyDefaults.applyStrict(to: $0) }
    #expect(values.count == 17)
    #expect(values.contains { $0.propertyName == "user_id" && $0.priority == 22 })
    #expect(values.contains { $0.propertyName == "session_id" && $0.priority == 13 })
    #expect(values.contains { $0.nameRegex?.contains("interaction") == true })
  }

  @Test("minimal GDPR contains five public rules")
  func minimalGDPR() throws {
    let values = try rules { try PrivacyDefaults.applyMinimal(to: $0) }
    #expect(values.count == 5)
    #expect(values.map(\.priority) == [20, 18, 16, 15, 0])
  }

  @Test("CCPA contains PII marketing and fallback rules")
  func ccpa() throws {
    let values = try rules { try PrivacyDefaults.applyCCPA(to: $0) }
    #expect(values.count == 3)
    #expect(values.map(\.priority) == [15, 12, 0])
  }

  @Test("privacy regions select the documented variants")
  func regions() throws {
    var counts: [PrivacyRegion: Int] = [:]
    for region in [PrivacyRegion.eu, .uk, .california, .global] {
      let builder = RoutingBuilder()
      try PrivacyDefaults.apply(to: builder, region: region)
      counts[region] = builder.build().rules.count
    }
    #expect(counts[.eu] == 17)
    #expect(counts[.uk] == 14)
    #expect(counts[.california] == 3)
    #expect(counts[.global] == 5)
  }

  @Test("base performance preset mirrors thirteen Flutter rules")
  func performance() throws {
    let values = try rules(PerformanceDefaults.apply)
    #expect(values.count == 13)
    #expect(values.first?.priority == 25)
    #expect(values.last?.samplingRate == 0.5)
    #expect(values.first { $0.nameRegex?.contains("animation") == true }?.samplingRate == 0.0001)
  }

  @Test("mobile performance adds three platform rules")
  func mobile() throws {
    let values = try rules(PerformanceDefaults.applyMobileOptimized)
    #expect(values.count == 16)
    #expect(values.first { $0.isHighVolume == true }?.samplingRate == 0.005)
    #expect(values.contains { $0.propertyName == "location" })
  }

  @Test("web performance adds navigation and DOM rules")
  func web() throws {
    let values = try rules(PerformanceDefaults.applyWebOptimized)
    #expect(values.count == 15)
    #expect(values.filter { $0.description?.hasPrefix("Web:") == true }.count == 2)
  }

  @Test("server performance adds HTTP database and cache rules")
  func server() throws {
    let values = try rules(PerformanceDefaults.applyServerOptimized)
    #expect(values.count == 16)
    #expect(values.filter { $0.description?.hasPrefix("Server:") == true }.count == 3)
  }

  @Test("low latency contains essential critical and fallback")
  func lowLatency() throws {
    let values = try rules(PerformanceDefaults.applyLowLatency)
    #expect(values.map(\.priority) == [20, 18, 0])
    #expect(values.last?.samplingRate == 0.01)
  }

  @Test("bandwidth-conscious fallback uses minimal sampling")
  func bandwidth() throws {
    let values = try rules(PerformanceDefaults.applyBandwidthConscious)
    #expect(values.count == 4)
    #expect(values.last?.samplingRate == 0.001)
  }

  @Test("high-throughput applies ultra-minimal rates")
  func throughput() throws {
    let values = try rules(PerformanceDefaults.applyHighThroughput)
    #expect(values.count == 4)
    #expect(values.last?.samplingRate == 0.00001)
    #expect(values.first { $0.isHighVolume == true }?.samplingRate == 0.0001)
  }

  private func rules(_ apply: (RoutingBuilder) throws -> Void) throws -> [RoutingRule] {
    let builder = RoutingBuilder()
    try apply(builder)
    return builder.build().rules
  }
}
