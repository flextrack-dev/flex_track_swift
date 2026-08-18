import Foundation
import Testing

@testable import FlexTrack

@Suite("Flutter-parity public utilities")
struct PublicUtilitiesTests {
  @Test("wildcards question marks and exact patterns are case insensitive")
  func patterns() {
    #expect(PatternMatcher.matches("purchase_completed", pattern: "purchase_*"))
    #expect(PatternMatcher.matches("debug_1", pattern: "debug_?"))
    #expect(PatternMatcher.matches("LOGIN", pattern: "login"))
    #expect(!PatternMatcher.matches("purchase", pattern: "login*"))
  }
  @Test("pattern collections prefix suffix and fragments use OR")
  func collections() {
    #expect(PatternMatcher.matchesAny("purchase", patterns: ["login", "pur*"]))
    #expect(PatternMatcher.startsWithAny("api_request", prefixes: ["web", "api"]))
    #expect(PatternMatcher.endsWithAny("request_error", suffixes: ["ok", "error"]))
    #expect(PatternMatcher.containsAny("checkout_complete", fragments: ["cart", "complete"]))
  }
  @Test("property matchers support exists equality wildcard and regex")
  func properties() {
    let values: [String: JSONValue] = ["plan": .string("premium"), "count": .number(2)]
    #expect(PatternMatcher.matchesProperty(values, name: "plan"))
    #expect(PatternMatcher.matchesProperty(values, name: "count", matcher: .equals(.number(2))))
    #expect(PatternMatcher.matchesProperty(values, name: "plan", matcher: .pattern("pre*")))
    #expect(PatternMatcher.matchesProperty(values, name: "plan", matcher: .regex("^prem")))
  }
  @Test("all and any property composition differ")
  func propertyComposition() {
    let values: [String: JSONValue] = ["plan": .string("pro")]
    let matchers: [String: PropertyMatcher] = ["plan": .equals(.string("pro")), "region": .exists]
    #expect(!PatternMatcher.matchesAllProperties(values, matchers: matchers))
    #expect(PatternMatcher.matchesAnyProperty(values, matchers: matchers))
  }
  @Test("every category pattern has a known match")
  func categories() {
    let examples: [(EventPatternCategory,String)] = [(.userInteraction,"click_button"),(.navigation,"page_view_home"),(.business,"purchase_done"),(.error,"crash_app"),(.performance,"latency_api"),(.debug,"debug_state"),(.system,"health_check"),(.network,"upload_file")]
    #expect(examples.allSatisfy { PatternMatcher.matchesCategory($0.1, category: $0.0) })
  }
  @Test("pattern validation and cache are bounded")
  func patternValidation() {
    PatternMatcher.clearCache(); #expect(PatternMatcher.validate("event_*").isValid); #expect(!PatternMatcher.validate("[broken").isValid)
    for index in 0...100 { _ = PatternMatcher.matches("value", pattern: "pattern_\(index)*") }
    #expect(PatternMatcher.cacheStats["size"]! <= 100); #expect(PatternMatcher.cacheStats["maxSize"] == 100)
  }
  @Test("deterministic decisions and buckets are stable")
  func deterministic() {
    #expect(SamplingUtils.deterministic("user", rate: 0.5) == SamplingUtils.deterministic("user", rate: 0.5))
    #expect(SamplingUtils.bucket("user", count: 10) == SamplingUtils.bucket("user", count: 10))
    #expect(SamplingUtils.bucket("user", count: 0) == 0)
  }
  @Test("seed makes random sampling reproducible")
  func seed() {
    SamplingUtils.setSeed(42); let first = (0..<20).map { _ in SamplingUtils.sample(0.5) }
    SamplingUtils.setSeed(42); #expect(first == (0..<20).map { _ in SamplingUtils.sample(0.5) })
  }
  @Test("sampling boundaries conversions and validation are exact")
  func boundaries() {
    #expect(!SamplingUtils.sample(0) && SamplingUtils.sample(1))
    #expect(SamplingUtils.percentageToRate(25) == 0.25 && SamplingUtils.rateToPercentage(0.25) == 25)
    #expect(!SamplingUtils.validateRate(.nan).isValid && !SamplingUtils.validateRate(1.1).isValid)
  }
  @Test("time reservoir adaptive weighted and bucket helpers cover boundaries")
  func helpers() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(SamplingUtils.byTime(interval: 100, now: now) && SamplingUtils.byTime(interval: 0, now: now))
    #expect(SamplingUtils.includeInReservoir(count: 3, size: 5))
    #expect(SamplingUtils.adaptiveRate(count: 200, target: 100) == 0.5)
    #expect(SamplingUtils.weighted(["critical": 1], eventType: "critical"))
  }
  @Test("statistics expose retained and dropped rates")
  func stats() {
    let value = SamplingUtils.stats([true,false,true,false])
    #expect(value.totalEvents == 4 && value.sampledEvents == 2 && value.droppedEvents == 2)
    #expect(value.actualSampleRate == 0.5 && value.dropRate == 0.5)
  }
  @Test("deterministic strategy respects stable identity")
  func strategy() {
    let value = SamplingUtils.strategy(.deterministic(0.5))
    #expect(value.shouldSample("event", userID: "user") == value.shouldSample("other", userID: "user")); value.reset()
  }
  @Test("tracker and event identifiers enforce limits")
  func identifiers() {
    #expect(ValidationUtils.trackerID("firebase_1").isValid)
    #expect(!ValidationUtils.trackerID("all").isValid && !ValidationUtils.trackerID("bad id").isValid)
    #expect(ValidationUtils.eventName("purchase.completed").isValid && !ValidationUtils.eventName("1purchase").isValid)
  }
  @Test("property validation covers keys counts types and finite numbers")
  func propertyValidation() {
    #expect(!ValidationUtils.propertyKey("timestamp").isValid && !ValidationUtils.propertyKey("bad-key").isValid)
    #expect(!ValidationUtils.propertyValue(.number(.nan)).isValid && !ValidationUtils.propertyValue(.array([])).isValid)
    let values = Dictionary(uniqueKeysWithValues: (0...50).map { ("key\($0)", JSONValue.number(Double($0))) })
    #expect(!ValidationUtils.eventProperties(values).isValid)
  }
  @Test("optional user and session IDs retain platform rules")
  func optionalIDs() {
    #expect(ValidationUtils.userID(nil).isValid && !ValidationUtils.userID("bad\nvalue").isValid)
    #expect(ValidationUtils.sessionID("session-1").isValid && !ValidationUtils.sessionID("bad session").isValid)
  }
  @Test("rate priority and tracker group boundaries are enforced")
  func validationBoundaries() {
    #expect(ValidationUtils.sampleRate(0).isValid && !ValidationUtils.sampleRate(.infinity).isValid)
    #expect(ValidationUtils.priority(-1000).isValid && !ValidationUtils.priority(1001).isValid)
    #expect(ValidationUtils.trackerGroup("analytics", ids: ["firebase","*"]).isValid)
    #expect(!ValidationUtils.trackerGroup("analytics", ids: ["firebase","firebase"]).isValid)
  }
  @Test("routing validation distinguishes warnings duplicates and valid rules")
  func routingValidation() {
    #expect(ValidationUtils.routing([]).isWarning)
    let rule = RoutingRule(id: "rule", targetGroup: TrackerGroup("analytics", trackerIDs: ["firebase"]), isDefault: true)
    let value = ValidationRuleData(rule)
    #expect(ValidationUtils.routing([value]).isValid && !ValidationUtils.routing([value,value]).isValid)
  }
  @Test("consent validation prioritizes PII safety")
  func consentValidation() {
    #expect(!ValidationUtils.consent(.init(isProduction: true, hasAnyConsent: false, hasPIIConsent: false, tracksPII: true, version: nil)).isValid)
    #expect(ValidationUtils.consent(.init(isProduction: true, hasAnyConsent: false, hasPIIConsent: false, tracksPII: false, version: nil)).isWarning)
    #expect(ValidationUtils.consent(.init(isProduction: false, hasAnyConsent: true, hasPIIConsent: true, tracksPII: false, version: "1")).isValid)
  }
}
