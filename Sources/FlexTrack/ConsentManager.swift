import Foundation

public enum ConsentType: String, CaseIterable, Codable, Sendable {
  case general, pii, marketing, analytics, performance
}

public struct ConsentSummary: Codable, Equatable, Sendable {
  public var general: Bool = false
  public var pii: Bool = false
  public var marketing: Bool = false
  public var analytics: Bool = false
  public var performance: Bool = false
  public var custom: [String: Bool] = [:]
  public var timestamp: Date?
  public var version: String?

  public var hasAnyConsent: Bool {
    general || pii || marketing || analytics || performance || custom.values.contains(true)
  }
  public var hasAllStandardConsents: Bool {
    general && pii && marketing && analytics && performance
  }
  public var routingState: ConsentState { ConsentState(general: general, pii: pii) }
}

/** Synchronous, thread-safe consent storage suitable for routing provider closures. */
public final class ConsentManager: @unchecked Sendable {
  private let lock = NSLock()
  private var value = ConsentSummary()
  private let now: @Sendable () -> Date

  public init(now: @escaping @Sendable () -> Date = Date.init) { self.now = now }
  public var summary: ConsentSummary { synchronized { value } }
  public var hasGeneralConsent: Bool { summary.general }
  public var hasPIIConsent: Bool { summary.pii }
  public var hasMarketingConsent: Bool { summary.marketing }
  public var hasAnalyticsConsent: Bool { summary.analytics }
  public var hasPerformanceConsent: Bool { summary.performance }
  public var hasAnyConsent: Bool { summary.hasAnyConsent }
  public var hasAllConsents: Bool { summary.hasAllStandardConsents }
  public var consentTimestamp: Date? { summary.timestamp }
  public var consentVersion: String? { summary.version }

  public func set(_ type: ConsentType, granted: Bool) {
    mutate {
      switch type {
      case .general: $0.general = granted
      case .pii: $0.pii = granted
      case .marketing: $0.marketing = granted
      case .analytics: $0.analytics = granted
      case .performance: $0.performance = granted
      }
    }
  }
  public func setGeneralConsent(_ granted: Bool) { set(.general, granted: granted) }
  public func setPIIConsent(_ granted: Bool) { set(.pii, granted: granted) }
  public func setMarketingConsent(_ granted: Bool) { set(.marketing, granted: granted) }
  public func setAnalyticsConsent(_ granted: Bool) { set(.analytics, granted: granted) }
  public func setPerformanceConsent(_ granted: Bool) { set(.performance, granted: granted) }

  public func setConsents(
    general: Bool? = nil, pii: Bool? = nil, marketing: Bool? = nil,
    analytics: Bool? = nil, performance: Bool? = nil, version: String? = nil
  ) {
    mutate {
      if let general { $0.general = general }
      if let pii { $0.pii = pii }
      if let marketing { $0.marketing = marketing }
      if let analytics { $0.analytics = analytics }
      if let performance { $0.performance = performance }
      if let version { $0.version = version }
    }
  }

  public func grantAllConsents(version: String? = nil) {
    setConsents(
      general: true, pii: true, marketing: true, analytics: true,
      performance: true, version: version)
  }
  public func revokeAllConsents() {
    mutate {
      $0.general = false; $0.pii = false; $0.marketing = false
      $0.analytics = false; $0.performance = false; $0.custom = [:]
    }
  }
  public func setCustomConsent(_ purpose: String, granted: Bool) throws {
    guard !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      throw FlexTrackConfigurationError.empty("consent purpose")
    }
    mutate { $0.custom[purpose] = granted }
  }
  public func customConsent(for purpose: String) -> Bool { summary.custom[purpose] ?? false }
  public var customConsents: [String: Bool] { summary.custom }
  public func removeCustomConsent(_ purpose: String) { mutate { $0.custom.removeValue(forKey: purpose) } }
  public func setConsentVersion(_ version: String) throws {
    guard !version.isEmpty else { throw FlexTrackConfigurationError.empty("consent version") }
    mutate { $0.version = version }
  }
  public func isAllowed(for type: ConsentType) -> Bool {
    let current = summary
    return switch type {
    case .general: current.general
    case .pii: current.pii
    case .marketing: current.marketing
    case .analytics: current.analytics
    case .performance: current.performance
    }
  }
  public func isConsentRequired(for type: ConsentType) -> Bool { !isAllowed(for: type) }

  public func validate() -> [String] {
    let current = summary
    var issues: [String] = []
    if current.general && !current.pii {
      issues.append("General consent granted but PII consent denied - may cause compliance issues")
    }
    if current.version == nil && current.hasAnyConsent {
      issues.append("Consent version not set - recommended for compliance tracking")
    }
    if current.timestamp == nil && current.hasAnyConsent {
      issues.append("Consent timestamp not set - required for compliance reporting")
    }
    return issues
  }

  public func encoded() throws -> Data {
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(summary)
  }
  public func load(_ data: Data) throws {
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ConsentSummary.self, from: data)
    synchronized { value = decoded }
  }

  private func mutate(_ body: (inout ConsentSummary) -> Void) {
    synchronized { body(&value); value.timestamp = now() }
  }
  @discardableResult
  private func synchronized<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock(); defer { lock.unlock() }; return try body()
  }
}
