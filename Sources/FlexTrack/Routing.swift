import Foundation

public struct ConsentState: Sendable, Equatable {
  public var general: Bool
  public var pii: Bool

  public init(general: Bool = false, pii: Bool = false) {
    self.general = general
    self.pii = pii
  }
}

public struct TrackerGroup: Sendable, Equatable {
  public let id: String
  public let trackerIDs: [String]

  public init(_ id: String, trackerIDs: [String]) {
    precondition(!id.isEmpty, "group id cannot be empty")
    self.id = id
    self.trackerIDs = trackerIDs.uniqued()
  }

  public static let all = TrackerGroup("all", trackerIDs: ["*"])
  public static let development = TrackerGroup("development", trackerIDs: ["console"])
}

public struct RoutingRule: Sendable {
  public let id: String?
  public let priority: Int
  public let targetGroup: TrackerGroup
  public let nameContains: String?
  public let nameRegex: String?
  public let category: String?
  public let propertyName: String?
  public let propertyValue: JSONValue?
  public let containsPII: Bool?
  public let isHighVolume: Bool?
  public let isEssential: Bool?
  public let isDefault: Bool
  public let requireConsent: Bool
  public let requirePIIConsent: Bool
  public let samplingRate: Double
  public let debugOnly: Bool
  public let productionOnly: Bool
  public let description: String?

  public init(
    id: String? = nil,
    priority: Int = 0,
    targetGroup: TrackerGroup,
    nameContains: String? = nil,
    nameRegex: String? = nil,
    category: String? = nil,
    propertyName: String? = nil,
    propertyValue: JSONValue? = nil,
    containsPII: Bool? = nil,
    isHighVolume: Bool? = nil,
    isEssential: Bool? = nil,
    isDefault: Bool = false,
    requireConsent: Bool = true,
    requirePIIConsent: Bool = true,
    samplingRate: Double = 1,
    debugOnly: Bool = false,
    productionOnly: Bool = false,
    description: String? = nil
  ) {
    precondition((0...1).contains(samplingRate), "sampling rate must be between 0 and 1")
    precondition(!(debugOnly && productionOnly), "a rule cannot target both environments")
    self.id = id
    self.priority = priority
    self.targetGroup = targetGroup
    self.nameContains = nameContains
    self.nameRegex = nameRegex
    self.category = category
    self.propertyName = propertyName
    self.propertyValue = propertyValue
    self.containsPII = containsPII
    self.isHighVolume = isHighVolume
    self.isEssential = isEssential
    self.isDefault = isDefault
    self.requireConsent = requireConsent
    self.requirePIIConsent = requirePIIConsent
    self.samplingRate = samplingRate
    self.debugOnly = debugOnly
    self.productionOnly = productionOnly
    self.description = description
  }

  fileprivate func matches(_ event: FlexEvent, isDebugMode: Bool) -> Bool {
    mismatchReasons(for: event, isDebugMode: isDebugMode).isEmpty
  }

  public func mismatchReasons(for event: FlexEvent, isDebugMode: Bool = false) -> [String] {
    var reasons: [String] = []
    if debugOnly && !isDebugMode { reasons.append("Rule is debug-only but debug mode is disabled") }
    if productionOnly && isDebugMode { reasons.append("Rule is production-only but debug mode is enabled") }
    if isDefault { return reasons }
    if let nameContains, !event.name.contains(nameContains) {
      reasons.append("Event name '\(event.name)' does not contain '\(nameContains)'")
    }
    if let nameRegex, event.name.range(of: nameRegex, options: .regularExpression) == nil {
      reasons.append("Event name '\(event.name)' does not match /\(nameRegex)/")
    }
    if let category, event.category != category {
      reasons.append("Category mismatch: expected \(category), got \(event.category ?? "nil")")
    }
    if let propertyName {
      if let actual = event.properties[propertyName] {
        if let propertyValue, actual != propertyValue {
          reasons.append("Property '\(propertyName)' value mismatch")
        }
      } else {
        reasons.append("Missing property '\(propertyName)'")
      }
    }
    if let containsPII, event.containsPII != containsPII { reasons.append("PII flag mismatch") }
    if let isHighVolume, event.isHighVolume != isHighVolume { reasons.append("High-volume flag mismatch") }
    if let isEssential, event.isEssential != isEssential { reasons.append("Essential flag mismatch") }
    return reasons
  }
}

public struct SkippedRule: Sendable, Equatable {
  public let ruleID: String?
  public let reason: String
}

public struct RoutingResult: Sendable, Equatable {
  public let targetTrackerIDs: [String]
  public let appliedPriorities: [Int]
  public let skippedRules: [SkippedRule]
  public let warnings: [String]
}

public struct RoutingConfiguration: Sendable {
  public let rules: [RoutingRule]
  public let defaultGroup: TrackerGroup?
  public let consentCheckingEnabled: Bool
  public let samplingEnabled: Bool
  public let isDebugMode: Bool
  public let customGroups: [String: TrackerGroup]
  public let customCategories: [String: String]

  public init(
    rules: [RoutingRule],
    defaultGroup: TrackerGroup? = nil,
    consentCheckingEnabled: Bool = true,
    samplingEnabled: Bool = true,
    isDebugMode: Bool = false,
    customGroups: [String: TrackerGroup] = [:],
    customCategories: [String: String] = [:]
  ) {
    self.rules = rules
    self.defaultGroup = defaultGroup
    self.consentCheckingEnabled = consentCheckingEnabled
    self.samplingEnabled = samplingEnabled
    self.isDebugMode = isDebugMode
    self.customGroups = customGroups
    self.customCategories = customCategories
  }

  public func validate() -> [String] {
    var issues: [String] = []
    let ids = rules.compactMap(\.id)
    let duplicates = Dictionary(grouping: ids, by: { $0 }).filter { $0.value.count > 1 }.keys
    if !duplicates.isEmpty { issues.append("Duplicate rule IDs found: \(duplicates.sorted().joined(separator: ", "))") }
    if !rules.contains(where: \.isDefault), defaultGroup == nil {
      issues.append("No default rule or default group specified")
    }
    let referenced = Set(rules.map(\.targetGroup.id))
    let unused = customGroups.keys.filter { !referenced.contains($0) }.sorted()
    if !unused.isEmpty { issues.append("Unreferenced custom groups: \(unused.joined(separator: ", "))") }
    return issues
  }
}

public struct RoutingEngine: Sendable {
  public let configuration: RoutingConfiguration

  public init(_ configuration: RoutingConfiguration) {
    self.configuration = configuration
  }

  public func route(
    _ event: FlexEvent,
    consent: ConsentState,
    availableTrackerIDs: Set<String>
  ) -> RoutingResult {
    let matching = configuration.rules.filter { $0.matches(event, isDebugMode: configuration.isDebugMode) }
    let nonDefault = matching.filter { !$0.isDefault }
    let candidates = nonDefault.isEmpty ? matching.filter(\.isDefault) : nonDefault
    let highestPriority = candidates.map(\.priority).max()
    let selected = highestPriority.map { value in candidates.filter { $0.priority == value } } ?? []
    let effectiveRules: [RoutingRule]
    if selected.isEmpty, let fallback = configuration.defaultGroup {
      effectiveRules = [RoutingRule(id: "default-group", targetGroup: fallback, isDefault: true)]
    } else {
      effectiveRules = selected
    }

    var targets: [String] = []
    var applied: [Int] = []
    var skipped: [SkippedRule] = []
    for rule in effectiveRules {
      if configuration.consentCheckingEnabled,
        rule.requireConsent,
        event.requiresConsent,
        !consent.general,
        !event.isEssential
      {
        skipped.append(SkippedRule(ruleID: rule.id, reason: "Consent requirements not met"))
        continue
      }
      if configuration.consentCheckingEnabled,
        rule.requirePIIConsent,
        event.containsPII,
        !consent.pii,
        !event.isEssential
      {
        skipped.append(SkippedRule(ruleID: rule.id, reason: "Consent requirements not met"))
        continue
      }
      if configuration.samplingEnabled,
        !event.isEssential,
        !DeterministicSampler.includes(event: event, rate: rule.samplingRate)
      {
        skipped.append(SkippedRule(ruleID: rule.id, reason: "Event was sampled out"))
        continue
      }
      let requested = rule.targetGroup.trackerIDs.contains("*")
        ? Array(availableTrackerIDs).sorted()
        : rule.targetGroup.trackerIDs
      targets.append(contentsOf: requested.filter(availableTrackerIDs.contains))
      applied.append(rule.priority)
    }
    let uniqueTargets = targets.uniqued()
    let warning = effectiveRules.isEmpty || (!applied.isEmpty && uniqueTargets.isEmpty)
      ? ["Rule resolved to no available trackers"] : []
    return RoutingResult(
      targetTrackerIDs: uniqueTargets,
      appliedPriorities: applied,
      skippedRules: skipped,
      warnings: warning
    )
  }

  public func debug(
    _ event: FlexEvent,
    consent: ConsentState = ConsentState(),
    availableTrackerIDs: Set<String> = []
  ) -> RoutingDebugInfo {
    let result = route(event, consent: consent, availableTrackerIDs: availableTrackerIDs)
    let appliedPriorities = result.appliedPriorities
    let decisions = configuration.rules.map { rule in
      let reasons = rule.mismatchReasons(for: event, isDebugMode: configuration.isDebugMode)
      let matched = reasons.isEmpty
      let applied = appliedPriorities.contains(rule.priority)
      let reason: String?
      if let skippedReason = result.skippedRules.first(where: { $0.ruleID == rule.id })?.reason {
        reason = skippedReason
      }
      else if !matched { reason = reasons.joined(separator: "; ") }
      else if !applied { reason = "Lower priority tier was not evaluated" }
      else { reason = nil }
      return RoutingRuleDecision(
        ruleID: rule.id, priority: rule.priority, matched: matched,
        applied: applied, reason: reason)
    }
    return RoutingDebugInfo(event: event, decisions: decisions, result: result)
  }

  public func validateConfiguration() -> [String] { configuration.validate() }
}

public struct RoutingRuleDecision: Sendable, Equatable {
  public let ruleID: String?
  public let priority: Int
  public let matched: Bool
  public let applied: Bool
  public let reason: String?
}

public struct RoutingDebugInfo: Sendable, Equatable {
  public let event: FlexEvent
  public let decisions: [RoutingRuleDecision]
  public let result: RoutingResult
}

public enum DeterministicSampler {
  public static func stableHash(_ value: String) -> UInt32 {
    var hash: UInt32 = 2_166_136_261
    for byte in value.utf8 {
      hash ^= UInt32(byte)
      hash = hash &* 16_777_619
    }
    return hash
  }

  public static func includes(event: FlexEvent, rate: Double) -> Bool {
    if rate >= 1 { return true }
    if rate <= 0 { return false }
    let key = event.userID ?? event.sessionID ?? event.name
    let hash = stableHash(key)
    return Double(hash) / Double(UInt32.max) < rate
  }
}

extension Array where Element: Hashable {
  fileprivate func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
