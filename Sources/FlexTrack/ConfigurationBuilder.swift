import Foundation

public enum FlexTrackConfigurationError: Error, Equatable, CustomStringConvertible {
  case empty(String)
  case unknownGroup(String)
  case unknownCategory(String)
  case missingTarget
  case invalidSamplingRate(Double)
  case missingTracker

  public var description: String {
    switch self {
    case .empty(let field): return "\(field) cannot be empty"
    case .unknownGroup(let name): return "unknown tracker group: \(name)"
    case .unknownCategory(let name): return "unknown event category: \(name)"
    case .missingTarget: return "route target is required"
    case .invalidSamplingRate(let value): return "sampling rate must be between 0 and 1: \(value)"
    case .missingTracker: return "at least one tracker is required"
    }
  }
}

public final class RoutingBuilder {
  private var rules: [RoutingRule] = []
  private var groups: [String: TrackerGroup] = [:]
  private var categories: [String: String] = [:]
  private var defaultGroup: TrackerGroup?
  private var samplingEnabled = true
  private var consentCheckingEnabled = true
  private var debugMode = false

  public init() {}

  @discardableResult
  public func defineGroup(_ name: String, trackerIDs: [String]) throws -> Self {
    guard !name.isEmpty else { throw FlexTrackConfigurationError.empty("group name") }
    guard !trackerIDs.isEmpty else { throw FlexTrackConfigurationError.empty("tracker IDs") }
    guard trackerIDs.allSatisfy({ !$0.isEmpty }) else {
      throw FlexTrackConfigurationError.empty("tracker ID")
    }
    groups[name] = TrackerGroup(name, trackerIDs: trackerIDs)
    return self
  }

  @discardableResult
  public func defineCategory(_ name: String) throws -> Self {
    guard !name.isEmpty else { throw FlexTrackConfigurationError.empty("category name") }
    categories[name] = name
    return self
  }

  @discardableResult
  public func setDefaultGroup(_ group: TrackerGroup) -> Self {
    defaultGroup = group
    return self
  }

  @discardableResult
  public func setDefaultGroup(named name: String) throws -> Self {
    guard let group = group(named: name) else { throw FlexTrackConfigurationError.unknownGroup(name) }
    defaultGroup = group
    return self
  }

  @discardableResult public func sampling(_ enabled: Bool) -> Self { samplingEnabled = enabled; return self }
  @discardableResult public func consentChecking(_ enabled: Bool) -> Self { consentCheckingEnabled = enabled; return self }
  @discardableResult public func debugMode(_ enabled: Bool) -> Self { debugMode = enabled; return self }

  @discardableResult
  public func routeNamed(
    _ pattern: String, configure: (RoutingRuleBuilder) throws -> Void
  ) throws -> Self {
    guard !pattern.isEmpty else { throw FlexTrackConfigurationError.empty("event name pattern") }
    return try add(.init(nameContains: pattern), configure)
  }

  @discardableResult
  public func routeMatching(
    _ pattern: String, configure: (RoutingRuleBuilder) throws -> Void
  ) throws -> Self {
    guard !pattern.isEmpty else { throw FlexTrackConfigurationError.empty("event name regex") }
    _ = try NSRegularExpression(pattern: pattern)
    return try add(.init(nameRegex: pattern), configure)
  }

  @discardableResult
  public func routeExact(
    _ name: String, configure: (RoutingRuleBuilder) throws -> Void
  ) throws -> Self {
    guard !name.isEmpty else { throw FlexTrackConfigurationError.empty("event name") }
    return try add(.init(nameRegex: "^\(NSRegularExpression.escapedPattern(for: name))$"), configure)
  }

  @discardableResult
  public func routeCategory(
    _ category: String, configure: (RoutingRuleBuilder) throws -> Void
  ) throws -> Self {
    guard allCategoryNames.contains(category) else {
      throw FlexTrackConfigurationError.unknownCategory(category)
    }
    return try add(.init(category: category), configure)
  }

  @discardableResult
  public func routeWithProperty(
    _ name: String, value: JSONValue? = nil,
    configure: (RoutingRuleBuilder) throws -> Void
  ) throws -> Self {
    guard !name.isEmpty else { throw FlexTrackConfigurationError.empty("property name") }
    return try add(.init(propertyName: name, propertyValue: value), configure)
  }

  @discardableResult public func routePII(configure: (RoutingRuleBuilder) throws -> Void) throws -> Self {
    try add(.init(containsPII: true), configure)
  }
  @discardableResult public func routeHighVolume(configure: (RoutingRuleBuilder) throws -> Void) throws -> Self {
    try add(.init(isHighVolume: true), configure)
  }
  @discardableResult public func routeEssential(configure: (RoutingRuleBuilder) throws -> Void) throws -> Self {
    try add(.init(isEssential: true), configure)
  }
  @discardableResult public func routeDefault(configure: (RoutingRuleBuilder) throws -> Void) throws -> Self {
    try add(.init(isDefault: true), configure)
  }

  @discardableResult public func addRule(_ rule: RoutingRule) -> Self { rules.append(rule); return self }
  @discardableResult public func addRules(_ values: [RoutingRule]) -> Self { rules.append(contentsOf: values); return self }
  @discardableResult public func clearRules() -> Self { rules.removeAll(); return self }
  @discardableResult public func removeRules(where predicate: (RoutingRule) -> Bool) -> Self {
    rules.removeAll(where: predicate); return self
  }

  @discardableResult
  public func applySmartDefaults() throws -> Self {
    try routeCategory("technical") { $0.toDevelopment().onlyInDebug().lightSampling().priority(8) }
      .routeHighVolume { $0.toAll().heavySampling().priority(5) }
      .routeDefault { $0.toAll() }
  }

  public func getGroup(named name: String) -> TrackerGroup? { group(named: name) }
  public func getCategory(named name: String) -> String? { allCategoryNames.contains(name) ? name : nil }
  public func getAllGroups() -> [TrackerGroup] { [.all, .development] + groups.values.sorted { $0.id < $1.id } }
  public func getAllCategories() -> [String] { allCategoryNames.sorted() }

  public func build() -> RoutingConfiguration {
    var output = rules
    if !output.contains(where: \.isDefault), defaultGroup == nil {
      output.append(RoutingRule(
        id: "auto-default", priority: -1000, targetGroup: .all,
        isDefault: true, requirePIIConsent: false,
        description: "Auto-generated default rule"))
    }
    return RoutingConfiguration(
      rules: output.enumerated().sorted {
        $0.element.priority == $1.element.priority
          ? $0.offset < $1.offset : $0.element.priority > $1.element.priority
      }.map(\.element),
      defaultGroup: defaultGroup,
      consentCheckingEnabled: consentCheckingEnabled,
      samplingEnabled: samplingEnabled,
      isDebugMode: debugMode,
      customGroups: groups,
      customCategories: categories)
  }

  public func validate() -> [String] { build().validate() }

  public func debugInfo() -> [String: Any] {
    [
      "rulesCount": rules.count,
      "customGroupsCount": groups.count,
      "customCategoriesCount": categories.count,
      "hasDefaultGroup": defaultGroup != nil,
      "enableSampling": samplingEnabled,
      "enableConsentChecking": consentCheckingEnabled,
      "isDebugMode": debugMode,
      "customGroups": groups.keys.sorted(),
      "customCategories": categories.keys.sorted(),
    ]
  }

  fileprivate func group(named name: String) -> TrackerGroup? {
    groups[name] ?? (name == "all" ? .all : (name == "development" ? .development : nil))
  }

  private var allCategoryNames: Set<String> {
    Set(["business", "user", "technical", "sensitive", "marketing", "system", "security"])
      .union(categories.keys)
  }

  private func add(
    _ condition: RuleCondition, _ configure: (RoutingRuleBuilder) throws -> Void
  ) throws -> Self {
    let builder = RoutingRuleBuilder(parent: self, condition: condition)
    try configure(builder)
    rules.append(try builder.build())
    return self
  }
}

fileprivate struct RuleCondition {
  var nameContains: String?
  var nameRegex: String?
  var category: String?
  var propertyName: String?
  var propertyValue: JSONValue?
  var containsPII: Bool?
  var isHighVolume: Bool?
  var isEssential: Bool?
  var isDefault = false
}

public final class RoutingRuleBuilder {
  private unowned let parent: RoutingBuilder
  private let condition: RuleCondition
  private var target: TrackerGroup?
  private var samplingRate = 1.0
  private var requireConsentValue = true
  private var requirePIIConsentValue = false
  private var debugOnlyValue = false
  private var productionOnlyValue = false
  private var priorityValue = 0
  private var idValue: String?
  private var descriptionValue: String?

  fileprivate init(parent: RoutingBuilder, condition: RuleCondition) {
    self.parent = parent
    self.condition = condition
  }

  @discardableResult public func toAll() -> Self { target = .all; return self }
  @discardableResult public func toDevelopment() -> Self { target = .development; return self }
  @discardableResult public func toGroup(_ group: TrackerGroup) -> Self { target = group; return self }
  @discardableResult public func toGroup(named name: String) throws -> Self {
    guard let group = parent.getGroup(named: name) else { throw FlexTrackConfigurationError.unknownGroup(name) }
    target = group; return self
  }
  @discardableResult public func to(_ trackerIDs: [String]) throws -> Self {
    guard !trackerIDs.isEmpty else { throw FlexTrackConfigurationError.empty("tracker IDs") }
    guard trackerIDs.allSatisfy({ !$0.isEmpty }) else { throw FlexTrackConfigurationError.empty("tracker ID") }
    target = TrackerGroup("custom-\(trackerIDs.joined(separator: "-"))", trackerIDs: trackerIDs)
    return self
  }
  @discardableResult public func toTracker(_ id: String) throws -> Self { try to([id]) }
  @discardableResult public func sample(_ rate: Double) throws -> Self {
    guard (0...1).contains(rate) else { throw FlexTrackConfigurationError.invalidSamplingRate(rate) }
    samplingRate = rate; return self
  }
  @discardableResult public func heavySampling() -> Self { samplingRate = 0.01; return self }
  @discardableResult public func lightSampling() -> Self { samplingRate = 0.1; return self }
  @discardableResult public func mediumSampling() -> Self { samplingRate = 0.5; return self }
  @discardableResult public func noSampling() -> Self { samplingRate = 1; return self }
  @discardableResult public func requireConsent() -> Self { requireConsentValue = true; return self }
  @discardableResult public func skipConsent() -> Self { requireConsentValue = false; return self }
  @discardableResult public func requirePIIConsent() -> Self { requirePIIConsentValue = true; return self }
  @discardableResult public func onlyInDebug() -> Self { debugOnlyValue = true; productionOnlyValue = false; return self }
  @discardableResult public func onlyInProduction() -> Self { productionOnlyValue = true; debugOnlyValue = false; return self }
  @discardableResult public func priority(_ value: Int) -> Self { priorityValue = value; return self }
  @discardableResult public func id(_ value: String) throws -> Self {
    guard !value.isEmpty else { throw FlexTrackConfigurationError.empty("rule ID") }
    idValue = value; return self
  }
  @discardableResult public func description(_ value: String) throws -> Self {
    guard !value.isEmpty else { throw FlexTrackConfigurationError.empty("description") }
    descriptionValue = value; return self
  }
  @discardableResult public func essential() -> Self {
    requireConsentValue = false; samplingRate = 1; priorityValue = 10; return self
  }

  fileprivate func build() throws -> RoutingRule {
    guard let target else { throw FlexTrackConfigurationError.missingTarget }
    return RoutingRule(
      id: idValue, priority: priorityValue, targetGroup: target,
      nameContains: condition.nameContains, nameRegex: condition.nameRegex,
      category: condition.category, propertyName: condition.propertyName,
      propertyValue: condition.propertyValue, containsPII: condition.containsPII,
      isHighVolume: condition.isHighVolume, isEssential: condition.isEssential,
      isDefault: condition.isDefault, requireConsent: requireConsentValue,
      requirePIIConsent: requirePIIConsentValue, samplingRate: samplingRate,
      debugOnly: debugOnlyValue, productionOnly: productionOnlyValue,
      description: descriptionValue)
  }
}

public final class FlexTrackBuilder {
  private var trackers: [any Tracker] = []
  private let routingBuilder = RoutingBuilder()
  private var queue: any EventQueue = InMemoryEventQueue()
  private var consentProvider: @Sendable () -> ConsentState = { ConsentState() }
  private var onlineProvider: @Sendable () -> Bool = { true }
  private var transformers: [EventTransformer] = []
  private var logger: FlexTrackLogger = .disabled

  public init() {}
  @discardableResult public func tracker(_ value: any Tracker) -> Self { trackers.append(value); return self }
  @discardableResult public func queue(_ value: any EventQueue) -> Self { queue = value; return self }
  @discardableResult public func consent(_ value: @escaping @Sendable () -> ConsentState) -> Self { consentProvider = value; return self }
  @discardableResult public func trackingContext(
    _ value: @escaping @Sendable () -> TrackingContext
  ) -> Self {
    consentProvider = { value().consentManager.summary.routingState }
    transformers.append { event in event.enriched(with: value().eventProperties) }
    return self
  }
  @discardableResult public func network(_ value: @escaping @Sendable () -> Bool) -> Self { onlineProvider = value; return self }
  @discardableResult public func transformer(_ value: @escaping EventTransformer) -> Self { transformers.append(value); return self }
  @discardableResult public func logger(_ value: FlexTrackLogger) -> Self { logger = value; return self }
  @discardableResult public func debugLogging() -> Self { logger = .debugConsole; return self }
  @discardableResult public func routing(_ configure: (RoutingBuilder) throws -> Void) rethrows -> Self {
    try configure(routingBuilder); return self
  }

  public func build(autoStart: Bool = true) async throws -> FlexTrackClient {
    guard !trackers.isEmpty else { throw FlexTrackConfigurationError.missingTracker }
    let client = FlexTrackClient(
      routingEngine: RoutingEngine(routingBuilder.build()), queue: queue,
      consentProvider: consentProvider, onlineProvider: onlineProvider, logger: logger)
    for tracker in trackers { try await client.register(tracker) }
    for transformer in transformers { await client.addTransformer(transformer) }
    if autoStart { try await client.start() }
    return client
  }
}
