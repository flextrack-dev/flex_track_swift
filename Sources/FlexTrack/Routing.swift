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
}

public struct RoutingRule: Sendable {
  public let id: String?
  public let priority: Int
  public let targetGroup: TrackerGroup
  public let nameContains: String?
  public let category: String?
  public let isDefault: Bool
  public let requireConsent: Bool
  public let requirePIIConsent: Bool
  public let samplingRate: Double

  public init(
    id: String? = nil,
    priority: Int = 0,
    targetGroup: TrackerGroup,
    nameContains: String? = nil,
    category: String? = nil,
    isDefault: Bool = false,
    requireConsent: Bool = true,
    requirePIIConsent: Bool = true,
    samplingRate: Double = 1
  ) {
    precondition((0...1).contains(samplingRate), "sampling rate must be between 0 and 1")
    self.id = id
    self.priority = priority
    self.targetGroup = targetGroup
    self.nameContains = nameContains
    self.category = category
    self.isDefault = isDefault
    self.requireConsent = requireConsent
    self.requirePIIConsent = requirePIIConsent
    self.samplingRate = samplingRate
  }

  fileprivate func matches(_ event: FlexEvent) -> Bool {
    if isDefault { return true }
    if let nameContains, !event.name.contains(nameContains) { return false }
    if let category, event.category != category { return false }
    return nameContains != nil || category != nil
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

  public init(
    rules: [RoutingRule],
    defaultGroup: TrackerGroup? = nil,
    consentCheckingEnabled: Bool = true,
    samplingEnabled: Bool = true
  ) {
    self.rules = rules
    self.defaultGroup = defaultGroup
    self.consentCheckingEnabled = consentCheckingEnabled
    self.samplingEnabled = samplingEnabled
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
    let matching = configuration.rules.filter { $0.matches(event) }
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
        skipped.append(SkippedRule(ruleID: rule.id, reason: "General consent is required"))
        continue
      }
      if configuration.consentCheckingEnabled,
        rule.requirePIIConsent,
        event.containsPII,
        !consent.pii
      {
        skipped.append(SkippedRule(ruleID: rule.id, reason: "PII consent is required"))
        continue
      }
      if configuration.samplingEnabled,
        !event.isEssential,
        !DeterministicSampler.includes(event: event, rate: rule.samplingRate)
      {
        skipped.append(SkippedRule(ruleID: rule.id, reason: "Event was sampled out"))
        continue
      }
      targets.append(contentsOf: rule.targetGroup.trackerIDs.filter(availableTrackerIDs.contains))
      applied.append(rule.priority)
    }
    let uniqueTargets = targets.uniqued()
    let warning =
      effectiveRules.isEmpty || (!targets.isEmpty && uniqueTargets.isEmpty)
      ? ["Rule resolved to no available trackers"] : []
    return RoutingResult(
      targetTrackerIDs: uniqueTargets,
      appliedPriorities: applied,
      skippedRules: skipped,
      warnings: warning
    )
  }
}

public enum DeterministicSampler {
  public static func includes(event: FlexEvent, rate: Double) -> Bool {
    if rate >= 1 { return true }
    if rate <= 0 { return false }
    let key = event.userID ?? event.sessionID ?? event.name
    var hash: UInt32 = 2_166_136_261
    for byte in key.utf8 {
      hash ^= UInt32(byte)
      hash = hash &* 16_777_619
    }
    return Double(hash) / Double(UInt32.max) < rate
  }
}

extension Array where Element: Hashable {
  fileprivate func uniqued() -> [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
