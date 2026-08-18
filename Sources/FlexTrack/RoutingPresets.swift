import Foundation

public enum SmartDefaults {
  public static func apply(to builder: RoutingBuilder) throws {
    try builder
      .routeCategory("technical") { $0.toDevelopment().onlyInDebug().lightSampling().priority(8); try $0.description("Technical events for debugging") }
      .routeHighVolume { $0.toAll().heavySampling().priority(5); try $0.description("High volume events with reduced sampling") }
      .routeCategory("security") { $0.toAll().essential().priority(15); try $0.description("Security events - always tracked") }
      .routeCategory("system") { $0.toAll().skipConsent().lightSampling().priority(7); try $0.description("System events - no consent required") }
      .routeCategory("sensitive") { $0.toAll().requireConsent().requirePIIConsent().priority(12); try $0.description("Sensitive events requiring full consent") }
      .routePII { $0.toAll().requirePIIConsent().priority(10); try $0.description("PII events requiring specific consent") }
      .routeEssential { $0.toAll().essential().priority(20); try $0.description("Essential events - bypass all restrictions") }
      .routeDefault { $0.toAll().priority(0); try $0.description("Default routing for unmatched events") }
  }

  public static func applyPerformanceFocused(to builder: RoutingBuilder) throws {
    try apply(to: builder)
    try builder
      .routeWithProperty("high_frequency") { $0.toAll().heavySampling().priority(6); try $0.description("High frequency events with heavy sampling") }
      .routeWithProperty("batchable") { $0.toAll().mediumSampling().priority(4); try $0.description("Batchable events with medium sampling") }
  }

  public static func applyPrivacyFocused(to builder: RoutingBuilder) throws {
    try builder
      .routeCategory("user") { $0.toAll().requireConsent().priority(9); try $0.description("User events requiring consent") }
      .routeCategory("marketing") { $0.toAll().requireConsent().priority(11); try $0.description("Marketing events requiring consent") }
    try apply(to: builder)
  }

  public static func applyDevelopmentFriendly(to builder: RoutingBuilder) throws {
    try builder
      .routeMatching("debug_.*") { $0.toDevelopment().onlyInDebug().noSampling().priority(15); try $0.description("Debug events for development") }
      .routeMatching("test_.*") { $0.toDevelopment().onlyInDebug().noSampling().priority(14); try $0.description("Test events for development") }
      .routeMatching("dev_.*") { $0.toDevelopment().onlyInDebug().noSampling().priority(13); try $0.description("Development-specific events") }
    try apply(to: builder)
  }
}

public enum PrivacyRegion: Sendable { case eu, uk, california, global }
public typealias GDPRRegion = PrivacyRegion

public enum PrivacyDefaults {
  public static func apply(to builder: RoutingBuilder, compliantTrackerIDs: [String] = []) throws {
    let target = try prepare(builder, compliantTrackerIDs)
    try builder
      .routeCategory("sensitive") { try $0.toGroup(named: target).requirePIIConsent().requireConsent().noSampling().priority(20).description("Sensitive data - GDPR compliant trackers only") }
      .routePII { try $0.toGroup(named: target).requirePIIConsent().noSampling().priority(18).description("PII events requiring explicit consent") }
      .routeCategory("user") { $0.toAll().requireConsent().mediumSampling().priority(12); try $0.description("User behavior events requiring consent") }
      .routeCategory("marketing") { $0.toAll().requireConsent().requirePIIConsent().lightSampling().priority(15); try $0.description("Marketing events requiring full consent") }
    try piiProperty("email", target, 19, "Events with email - PII consent required", builder)
    try piiProperty("phone", target, 19, "Events with phone - PII consent required", builder)
    try piiProperty("ip_address", target, 19, "Events with IP address - PII consent required", builder)
    try piiProperty("location", target, 17, "Location data - strict PII consent required", builder)
    try piiProperty("latitude", target, 17, "GPS coordinates - strict PII consent required", builder)
    try builder
      .routeCategory("security") { $0.toAll().skipConsent().noSampling().priority(25); try $0.description("Security events - legitimate interest basis") }
      .routeEssential { $0.toAll().skipConsent().noSampling().priority(24); try $0.description("Essential events - legitimate interest basis") }
      .routeCategory("system") { $0.toAll().skipConsent().lightSampling().priority(8); try $0.description("System events - no personal data") }
      .routeCategory("technical") { $0.toDevelopment().skipConsent().lightSampling().onlyInDebug().priority(6); try $0.description("Technical events - anonymous debug data") }
      .routeDefault { $0.toAll().requireConsent().mediumSampling().priority(0); try $0.description("Default GDPR-compliant routing") }
  }

  public static func applyStrict(to builder: RoutingBuilder, compliantTrackerIDs: [String] = []) throws {
    try apply(to: builder, compliantTrackerIDs: compliantTrackerIDs)
    let target = targetName(compliantTrackerIDs)
    try builder
      .routeWithProperty("user_id") { try $0.toGroup(named: target).requirePIIConsent().noSampling().priority(22).description("User ID events - strict PII consent") }
      .routeWithProperty("session_id") { try $0.toGroup(named: target).requireConsent().lightSampling().priority(13).description("Session tracking - consent required") }
      .routeMatching("(click|view|scroll|interaction)_.*") { $0.toAll().requireConsent().mediumSampling().priority(14); try $0.description("Behavioral events - consent required") }
  }

  public static func applyMinimal(to builder: RoutingBuilder, compliantTrackerIDs: [String] = []) throws {
    let target = try prepare(builder, compliantTrackerIDs)
    try builder
      .routePII { try $0.toGroup(named: target).requirePIIConsent().priority(16).description("PII events - minimal GDPR compliance") }
      .routeCategory("sensitive") { try $0.toGroup(named: target).requirePIIConsent().priority(15).description("Sensitive events - minimal GDPR compliance") }
      .routeEssential { $0.toAll().skipConsent().priority(20); try $0.description("Essential events - legitimate interest") }
      .routeCategory("security") { $0.toAll().skipConsent().priority(18); try $0.description("Security events - legitimate interest") }
      .routeDefault { $0.toAll().priority(0); try $0.description("Default minimal GDPR routing") }
  }

  public static func applyCCPA(to builder: RoutingBuilder, compliantTrackerIDs: [String] = []) throws {
    let target = try prepare(builder, compliantTrackerIDs)
    try builder
      .routePII { try $0.toGroup(named: target).requireConsent().priority(15).description("PII events - CCPA compliance") }
      .routeCategory("marketing") { $0.toAll().requireConsent().priority(12); try $0.description("Marketing events - CCPA compliance") }
      .routeDefault { $0.toAll().priority(0); try $0.description("Default CCPA-compliant routing") }
  }

  public static func apply(to builder: RoutingBuilder, region: PrivacyRegion, compliantTrackerIDs: [String] = []) throws {
    switch region {
    case .eu: try applyStrict(to: builder, compliantTrackerIDs: compliantTrackerIDs)
    case .uk: try apply(to: builder, compliantTrackerIDs: compliantTrackerIDs)
    case .california: try applyCCPA(to: builder, compliantTrackerIDs: compliantTrackerIDs)
    case .global: try applyMinimal(to: builder, compliantTrackerIDs: compliantTrackerIDs)
    }
  }

  private static func prepare(_ builder: RoutingBuilder, _ trackers: [String]) throws -> String {
    if !trackers.isEmpty { try builder.defineGroup("gdpr_compliant", trackerIDs: trackers) }
    return targetName(trackers)
  }
  private static func targetName(_ trackers: [String]) -> String { trackers.isEmpty ? "all" : "gdpr_compliant" }
  private static func piiProperty(_ name: String, _ target: String, _ priority: Int, _ text: String, _ builder: RoutingBuilder) throws {
    try builder.routeWithProperty(name) { try $0.toGroup(named: target).requirePIIConsent().noSampling().priority(priority).description(text) }
  }
}

public typealias GDPRDefaults = PrivacyDefaults

public enum PerformanceDefaults {
  public static func apply(to builder: RoutingBuilder) throws {
    try sampledHighVolume(0.01, 15, "High volume events - aggressive sampling", builder)
    try sampledRegex("(click|tap|scroll|swipe|gesture)_.*", 0.01, 12, "UI interaction events - heavy sampling", builder)
    try sampledRegex("(mouse|pointer|hover)_.*", 0.001, 14, "Mouse/pointer events - extreme sampling", builder)
    try sampledRegex("scroll_.*", 0.01, 13, "Scroll events - heavy sampling", builder)
    try sampledRegex("(heartbeat|ping|alive)_.*", 0.05, 11, "Heartbeat events - moderate sampling", builder)
    try builder.routeCategory("technical") { $0.toDevelopment().onlyInDebug().lightSampling().priority(8); try $0.description("Performance events - debug only") }
    try sampledRegex("(api|network|http|request)_.*", 0.1, 9, "Network events - light sampling", builder)
    try sampledRegex("(timer|interval|periodic)_.*", 0.02, 10, "Timer events - heavy sampling", builder)
    try sampledRegex("(frame|animation|render)_.*", 0.0001, 16, "Animation events - minimal sampling", builder)
    try sampledRegex("(purchase|payment|transaction|error)_.*", 1, 20, "Critical events - no sampling", builder)
    try builder
      .routeEssential { $0.toAll().noSampling().priority(25); try $0.description("Essential events - no sampling") }
      .routeCategory("security") { $0.toAll().noSampling().priority(22); try $0.description("Security events - no sampling") }
      .routeDefault { $0.toAll().mediumSampling().priority(0); try $0.description("Default performance-optimized routing") }
  }

  public static func applyMobileOptimized(to builder: RoutingBuilder) throws {
    try sampledHighVolume(0.005, 15, "Mobile: Ultra-aggressive sampling for high volume", builder)
    try sampledRegex("(touch|swipe|pinch|rotate|shake)_.*", 0.01, 12, "Mobile: Touch events with heavy sampling", builder)
    try builder.routeWithProperty("location") { try $0.toAll().sample(0.1).priority(13).description("Mobile: Location events - battery conscious") }
    try apply(to: builder)
  }
  public static func applyWebOptimized(to builder: RoutingBuilder) throws {
    try sampledRegex("(page_view|route_change|navigation)_.*", 0.1, 14, "Web: Navigation events with light sampling", builder)
    try sampledRegex("(focus|blur|resize|load)_.*", 0.05, 11, "Web: DOM events with moderate sampling", builder)
    try apply(to: builder)
  }
  public static func applyServerOptimized(to builder: RoutingBuilder) throws {
    try sampledRegex("(request|response|endpoint)_.*", 0.5, 12, "Server: HTTP events with medium sampling", builder)
    try sampledRegex("(query|database|sql)_.*", 0.1, 11, "Server: Database events with light sampling", builder)
    try sampledRegex("(cache|redis|memcached)_.*", 0.01, 10, "Server: Cache events with heavy sampling", builder)
    try apply(to: builder)
  }
  public static func applyLowLatency(to builder: RoutingBuilder) throws {
    try builder.routeEssential { $0.toAll().noSampling().priority(20); try $0.description("Low-latency: Essential events only") }
    try sampledRegex("(error|failure|critical)_.*", 1, 18, "Low-latency: Critical events only", builder)
    try builder.routeDefault { try $0.toAll().sample(0.01).priority(0).description("Low-latency: Minimal default tracking") }
  }
  public static func applyBandwidthConscious(to builder: RoutingBuilder) throws {
    try builder.routeEssential { $0.toAll().noSampling().priority(20); try $0.description("Bandwidth: Essential events only") }
    try sampledRegex("(purchase|payment|signup|login)_.*", 1, 18, "Bandwidth: Business-critical events", builder)
    try sampledRegex("(error|crash|exception)_.*", 0.1, 15, "Bandwidth: Error events with sampling", builder)
    try builder.routeDefault { try $0.toAll().sample(0.001).priority(0).description("Bandwidth: Minimal default tracking") }
  }
  public static func applyHighThroughput(to builder: RoutingBuilder) throws {
    try sampledHighVolume(0.0001, 15, "High-throughput: Ultra-minimal sampling", builder)
    try builder.routeEssential { try $0.toAll().sample(0.1).priority(20).description("High-throughput: Sampled essential events") }
    try sampledRegex("error_.*", 0.01, 18, "High-throughput: Sampled error tracking", builder)
    try builder.routeDefault { try $0.toAll().sample(0.00001).priority(0).description("High-throughput: Extremely minimal default") }
  }

  private static func sampledRegex(_ pattern: String, _ rate: Double, _ priority: Int, _ text: String, _ builder: RoutingBuilder) throws {
    try builder.routeMatching(pattern) { try $0.toAll().sample(rate).priority(priority).description(text) }
  }
  private static func sampledHighVolume(_ rate: Double, _ priority: Int, _ text: String, _ builder: RoutingBuilder) throws {
    try builder.routeHighVolume { try $0.toAll().sample(rate).priority(priority).description(text) }
  }
}
