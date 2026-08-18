import Foundation

public enum EventPatternCategory: CaseIterable, Sendable { case userInteraction, navigation, business, error, performance, debug, system, network }
public enum PropertyMatcher: Sendable {
  case exists, equals(JSONValue), pattern(String), regex(String)
}
public struct PatternValidationResult: Sendable, Equatable { public let isValid: Bool; public let error: String? }

public enum PatternMatcher {
  private static let cache = RegexCache()
  public static func matches(_ value: String, pattern: String) -> Bool {
    if pattern == "*" || value == pattern { return true }
    return regexMatches(value, pattern: "^\(pattern.replacingOccurrences(of: "*", with: ".*").replacingOccurrences(of: "?", with: "."))$")
  }
  public static func regexMatches(_ value: String, pattern: String) -> Bool { (try? cache.regex(pattern).firstMatch(in: value, range: NSRange(value.startIndex..., in: value))) != nil }
  public static func matchesAny(_ value: String, patterns: [String]) -> Bool { patterns.contains { matches(value, pattern: $0) } }
  public static func matchesAnyRegex(_ value: String, patterns: [String]) -> Bool { patterns.contains { regexMatches(value, pattern: $0) } }
  public static func startsWithAny(_ value: String, prefixes: [String]) -> Bool { prefixes.contains { value.hasPrefix($0) } }
  public static func endsWithAny(_ value: String, suffixes: [String]) -> Bool { suffixes.contains { value.hasSuffix($0) } }
  public static func containsAny(_ value: String, fragments: [String]) -> Bool { fragments.contains { value.contains($0) } }
  public static func matchesProperty(_ properties: [String: JSONValue]?, name: String, matcher: PropertyMatcher = .exists) -> Bool {
    guard let actual = properties?[name] else { return false }
    switch matcher {
    case .exists: return true
    case .equals(let expected): return actual == expected
    case .pattern(let pattern): if case .string(let value) = actual { return matches(value, pattern: pattern) }; return false
    case .regex(let pattern): if case .string(let value) = actual { return regexMatches(value, pattern: pattern) }; return false
    }
  }
  public static func matchesAllProperties(_ properties: [String: JSONValue]?, matchers: [String: PropertyMatcher]) -> Bool { properties != nil && matchers.allSatisfy { matchesProperty(properties, name: $0.key, matcher: $0.value) } }
  public static func matchesAnyProperty(_ properties: [String: JSONValue]?, matchers: [String: PropertyMatcher]) -> Bool { properties != nil && matchers.contains { matchesProperty(properties, name: $0.key, matcher: $0.value) } }
  public static func categoryPattern(_ category: EventPatternCategory) -> String { switch category {
    case .userInteraction: "(click|tap|touch|swipe|scroll|input|select|focus|blur)_.*"
    case .navigation: "(page_view|navigate|route|screen|tab)_.*"
    case .business: "(purchase|payment|signup|login|subscription|conversion)_.*"
    case .error: "(error|exception|crash|failure|timeout)_.*"
    case .performance: "(load|render|response|latency|memory|cpu)_.*"
    case .debug: "(debug|test|dev|trace|log)_.*"
    case .system: "(system|health|heartbeat|status|config)_.*"
    case .network: "(api|http|request|response|network|download|upload)_.*"
  } }
  public static func matchesCategory(_ value: String, category: EventPatternCategory) -> Bool { regexMatches(value, pattern: categoryPattern(category)) }
  public static func validate(_ pattern: String) -> PatternValidationResult { do { _ = try NSRegularExpression(pattern: pattern.contains("*") || pattern.contains("?") ? "^\(pattern.replacingOccurrences(of: "*", with: ".*").replacingOccurrences(of: "?", with: "."))$" : pattern); return .init(isValid: true, error: nil) } catch { return .init(isValid: false, error: "Invalid pattern: \(error)") } }
  public static func clearCache() { cache.clear() }
  public static var cacheStats: [String: Int] { ["size": cache.size, "maxSize": 100] }
}

private final class RegexCache: @unchecked Sendable {
  private let lock = NSLock(); private var values: [String: NSRegularExpression] = [:]
  func regex(_ pattern: String) throws -> NSRegularExpression { lock.lock(); defer { lock.unlock() }; if let value = values[pattern] { return value }; if values.count >= 100 { values.removeAll() }; let value = try NSRegularExpression(pattern: pattern, options: .caseInsensitive); values[pattern] = value; return value }
  func clear() { lock.lock(); values.removeAll(); lock.unlock() }
  var size: Int { lock.lock(); defer { lock.unlock() }; return values.count }
}

public struct RateValidation: Sendable, Equatable { public let isValid: Bool; public let error: String? }
public struct SamplingStats: Sendable, Equatable {
  public let totalEvents: Int; public let sampledEvents: Int
  public var droppedEvents: Int { totalEvents - sampledEvents }
  public var actualSampleRate: Double { totalEvents == 0 ? 0 : Double(sampledEvents) / Double(totalEvents) }
  public var dropRate: Double { 1 - actualSampleRate }
}
public enum SamplingType: Sendable { case random, deterministic, timeBased, adaptive, backoff }
public struct SamplingConfig: Sendable {
  public let type: SamplingType; public let rate: Double; public let interval: TimeInterval?; public let target: Int?; public let factor: Double?
  public static func random(_ rate: Double) -> Self { .init(type: .random, rate: rate, interval: nil, target: nil, factor: nil) }
  public static func deterministic(_ rate: Double) -> Self { .init(type: .deterministic, rate: rate, interval: nil, target: nil, factor: nil) }
  public static func timeBased(_ interval: TimeInterval) -> Self { .init(type: .timeBased, rate: 1, interval: interval, target: nil, factor: nil) }
  public static func adaptive(window: TimeInterval, target: Int) -> Self { .init(type: .adaptive, rate: 1, interval: window, target: target, factor: nil) }
  public static func backoff(_ rate: Double, factor: Double = 0.5) -> Self { .init(type: .backoff, rate: rate, interval: nil, target: nil, factor: factor) }
}

public enum SamplingUtils {
  private static let generator = SeededGenerator()
  public static func sample(_ rate: Double) -> Bool { if rate >= 1 { return true }; if rate <= 0 { return false }; return generator.nextDouble() < rate }
  public static func deterministic(_ key: String, rate: Double) -> Bool { if rate >= 1 { return true }; if rate <= 0 { return false }; return Double(DeterministicSampler.stableHash(key)) / 4_294_967_296 < rate }
  public static func key(for event: FlexEvent) -> String { if let id = event.userID, !id.isEmpty { return id }; if let id = event.sessionID, !id.isEmpty { return id }; return event.name }
  public static func byUser(_ id: String?, rate: Double) -> Bool { guard let id, !id.isEmpty else { return sample(rate) }; return deterministic(id, rate: rate) }
  public static func bySession(_ id: String?, rate: Double) -> Bool { guard let id, !id.isEmpty else { return sample(rate) }; return deterministic(id, rate: rate) }
  public static func byEventName(_ name: String, rate: Double) -> Bool { deterministic(name, rate: rate) }
  public static func byTime(interval: TimeInterval, now: Date = Date()) -> Bool { interval <= 0 || now.timeIntervalSince1970.truncatingRemainder(dividingBy: interval) == 0 }
  public static func withBackoff(count: Int, baseRate: Double, factor: Double = 0.5) -> Bool { sample(min(1, max(0, baseRate * pow(factor, Double(max(0, count - 1)))))) }
  public static func includeInReservoir(count: Int, size: Int) -> Bool { count <= size || sample(Double(size) / Double(count)) }
  public static func adaptiveRate(count: Int, target: Int) -> Double { count <= target ? 1 : min(1, max(0.001, Double(target) / Double(count))) }
  public static func weighted(_ weights: [String: Double], eventType: String) -> Bool { sample(weights[eventType] ?? 1) }
  public static func bucket(_ identifier: String, count: Int) -> Int { count <= 0 ? 0 : Int(DeterministicSampler.stableHash(identifier) % UInt32(count)) }
  public static func inBuckets(_ identifier: String, count: Int, targets: [Int]) -> Bool { targets.contains(bucket(identifier, count: count)) }
  public static func setSeed(_ seed: UInt64) { generator.seed(seed) }
  public static var seed: UInt64 { generator.currentSeed }
  public static func resetSeed() { generator.seed(UInt64(Date().timeIntervalSince1970 * 1000)) }
  public static func validateRate(_ rate: Double) -> RateValidation { if !rate.isFinite { return .init(isValid: false, error: "Sample rate must be a valid number") }; if rate < 0 { return .init(isValid: false, error: "Sample rate cannot be negative") }; if rate > 1 { return .init(isValid: false, error: "Sample rate cannot exceed 1.0") }; return .init(isValid: true, error: nil) }
  public static func percentageToRate(_ value: Double) -> Double { min(1, max(0, value / 100)) }
  public static func rateToPercentage(_ value: Double) -> Double { min(100, max(0, value * 100)) }
  public static func stats(_ results: [Bool]) -> SamplingStats { .init(totalEvents: results.count, sampledEvents: results.filter { $0 }.count) }
  public static func strategy(_ config: SamplingConfig, now: @escaping @Sendable () -> Date = Date.init) -> SamplingStrategy { SamplingStrategy(config, now: now) }
}

private final class SeededGenerator: @unchecked Sendable {
  private let lock = NSLock(); private var state: UInt64 = 1; private var initial: UInt64 = 1
  func seed(_ value: UInt64) { lock.lock(); initial = value; state = value; lock.unlock() }
  var currentSeed: UInt64 { lock.lock(); defer { lock.unlock() }; return initial }
  func nextDouble() -> Double { lock.lock(); defer { lock.unlock() }; state = state &* 6_364_136_223_846_793_005 &+ 1; return Double(state >> 11) / Double(UInt64(1) << 53) }
}

public final class SamplingStrategy: @unchecked Sendable {
  private let config: SamplingConfig; private let now: @Sendable () -> Date; private let lock = NSLock(); private var counts: [String: Int] = [:]; private var last: [String: Date] = [:]
  init(_ config: SamplingConfig, now: @escaping @Sendable () -> Date) { self.config = config; self.now = now }
  public func shouldSample(_ eventName: String, userID: String? = nil, sessionID: String? = nil) -> Bool { lock.lock(); defer { lock.unlock() }; switch config.type {
    case .random: return SamplingUtils.sample(config.rate)
    case .deterministic: return SamplingUtils.deterministic(userID ?? sessionID ?? eventName, rate: config.rate)
    case .timeBased: return config.interval.map { SamplingUtils.byTime(interval: $0, now: now()) } ?? false
    case .adaptive: let current = now(); if last[eventName].map({ current.timeIntervalSince($0) > (config.interval ?? 60) }) ?? true { counts[eventName] = 0 }; counts[eventName, default: 0] += 1; last[eventName] = current; return SamplingUtils.sample(SamplingUtils.adaptiveRate(count: counts[eventName]!, target: config.target ?? 100))
    case .backoff: let count = counts[eventName, default: 0]; counts[eventName] = count + 1; return SamplingUtils.withBackoff(count: count, baseRate: config.rate, factor: config.factor ?? 0.5)
  } }
  public func reset() { lock.lock(); counts.removeAll(); last.removeAll(); lock.unlock() }
}

public struct ValidationResult: Sendable, Equatable { public let isValid: Bool; public let isWarning: Bool; public let message: String?; public static let valid = Self(isValid: true, isWarning: false, message: nil); public static func invalid(_ text: String) -> Self { .init(isValid: false, isWarning: false, message: text) }; public static func warning(_ text: String) -> Self { .init(isValid: true, isWarning: true, message: text) } }
public struct ValidationGroup: Sendable { public let name: String; public let trackerIDs: [String] }
public struct ValidationRuleData: Sendable { public let id: String?; public let rate: Double; public let priority: Int; public let debugOnly: Bool; public let productionOnly: Bool; public let isDefault: Bool; public let group: ValidationGroup?; public init(_ rule: RoutingRule) { id = rule.id; rate = rule.samplingRate; priority = rule.priority; debugOnly = rule.debugOnly; productionOnly = rule.productionOnly; isDefault = rule.isDefault; group = .init(name: rule.targetGroup.id, trackerIDs: rule.targetGroup.trackerIDs) } }
public struct ConsentValidationData: Sendable { public let isProduction: Bool; public let hasAnyConsent: Bool; public let hasPIIConsent: Bool; public let tracksPII: Bool; public let version: String? }

public enum ValidationUtils {
  private static let tracker = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_-]+$"); private static let event = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_.-]+$"); private static let property = try! NSRegularExpression(pattern: "^[a-zA-Z0-9_]+$")
  private static func full(_ regex: NSRegularExpression, _ value: String) -> Bool { regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))?.range.length == value.utf16.count }
  public static func trackerID(_ value: String?) -> ValidationResult { guard let value, !value.isEmpty else { return .invalid("Tracker ID cannot be null or empty") }; if value.count > 50 { return .invalid("Tracker ID cannot exceed 50 characters") }; if !full(tracker, value) { return .invalid("Tracker ID can only contain letters, numbers, underscores, and hyphens") }; if ["all","none","default","system"].contains(value.lowercased()) { return .invalid("Tracker ID '\(value)' is reserved") }; return .valid }
  public static func eventName(_ value: String?) -> ValidationResult { guard let value, !value.isEmpty else { return .invalid("Event name cannot be null or empty") }; if value.count > 100 { return .invalid("Event name cannot exceed 100 characters") }; if !full(event, value) { return .invalid("Event name can only contain letters, numbers, underscores, dots, and hyphens") }; if !value.first!.isLetter { return .invalid("Event name must start with a letter") }; return .valid }
  public static func propertyKey(_ value: String) -> ValidationResult { if value.isEmpty { return .invalid("Property key cannot be empty") }; if value.count > 30 { return .invalid("Property key cannot exceed 30 characters") }; if !full(property, value) { return .invalid("Property key can only contain letters, numbers, and underscores") }; if ["timestamp","event_name","user_id","session_id","device_id","app_version","platform","environment"].contains(value.lowercased()) { return .invalid("Property key '\(value)' is reserved") }; return .valid }
  public static func propertyValue(_ value: JSONValue) -> ValidationResult { switch value { case .string(let text): return text.count > 1000 ? .invalid("String property value cannot exceed 1000 characters") : .valid; case .number(let number): return number.isFinite ? .valid : .invalid("Numeric property value cannot be NaN or infinite"); case .bool: return .valid; default: return .invalid("Property value must be string, number, bool, or date") } }
  public static func eventProperties(_ values: [String: JSONValue]?) -> ValidationResult { guard let values else { return .valid }; if values.count > 50 { return .invalid("Event cannot have more than 50 properties") }; for (key,value) in values { let keyResult = propertyKey(key); if !keyResult.isValid { return .invalid("Invalid property key '\(key)': \(keyResult.message!)") }; let valueResult = propertyValue(value); if !valueResult.isValid { return .invalid("Invalid property value for '\(key)': \(valueResult.message!)") } }; return .valid }
  public static func userID(_ value: String?) -> ValidationResult { guard let value, !value.isEmpty else { return .valid }; if value.count > 100 { return .invalid("User ID cannot exceed 100 characters") }; if value.contains(where: { $0 == "\n" || $0 == "\r" || $0 == "\t" }) { return .invalid("User ID cannot contain newlines or tabs") }; return .valid }
  public static func sessionID(_ value: String?) -> ValidationResult { guard let value, !value.isEmpty else { return .valid }; if value.count > 100 { return .invalid("Session ID cannot exceed 100 characters") }; return full(tracker,value) ? .valid : .invalid("Session ID can only contain letters, numbers, underscores, and hyphens") }
  public static func sampleRate(_ value: Double) -> ValidationResult { if !value.isFinite { return .invalid("Sample rate must be a valid number") }; if value < 0 { return .invalid("Sample rate cannot be negative") }; if value > 1 { return .invalid("Sample rate cannot exceed 1.0") }; return .valid }
  public static func priority(_ value: Int) -> ValidationResult { (-1000...1000).contains(value) ? .valid : .invalid("Rule priority must be between -1000 and 1000") }
  public static func trackerGroup(_ name: String, ids: [String]) -> ValidationResult { let n = trackerID(name); if !n.isValid { return .invalid("Invalid group name: \(n.message!)") }; if ids.isEmpty { return .invalid("Tracker group must contain at least one tracker ID") }; if ids.count > 20 { return .invalid("Tracker group cannot contain more than 20 trackers") }; for id in ids where id != "*" { let result = trackerID(id); if !result.isValid { return .invalid("Invalid tracker ID '\(id)': \(result.message!)") } }; if Set(ids).count != ids.count { return .invalid("Tracker group contains duplicate tracker IDs") }; return .valid }
  public static func routing(_ rules: [ValidationRuleData]) -> ValidationResult { if rules.isEmpty { return .warning("No routing rules defined - events may not be tracked") }; if rules.count > 100 { return .invalid("Too many routing rules (max 100)") }; let ids = rules.compactMap(\.id); if Set(ids).count != ids.count { return .invalid("Duplicate rule IDs found") }; if !rules.contains(where: \.isDefault) { return .warning("No default routing rule - unmatched events may not be tracked") }; for rule in rules { let result = routingRule(rule); if !result.isValid { return .invalid("Invalid routing rule: \(result.message!)") } }; return .valid }
  public static func routingRule(_ rule: ValidationRuleData) -> ValidationResult { if let id = rule.id { let result = trackerID(id); if !result.isValid { return .invalid("Invalid rule ID: \(result.message!)") } }; let rate = sampleRate(rule.rate); if !rate.isValid { return rate }; let p = priority(rule.priority); if !p.isValid { return p }; if let group = rule.group { let result = trackerGroup(group.name, ids: group.trackerIDs); if !result.isValid { return .invalid("Invalid target group: \(result.message!)") } }; if rule.debugOnly && rule.productionOnly { return .invalid("Rule cannot be both debug-only and production-only") }; return .valid }
  public static func consent(_ data: ConsentValidationData) -> ValidationResult { if data.tracksPII && !data.hasPIIConsent { return .invalid("PII consent required when tracking personally identifiable information") }; if data.isProduction && !data.hasAnyConsent { return .warning("No consent configured in production environment") }; if data.hasAnyConsent && data.version == nil { return .warning("Consent version not set - recommended for compliance tracking") }; return .valid }
}
