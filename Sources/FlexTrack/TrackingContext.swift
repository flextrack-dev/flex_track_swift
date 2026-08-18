import Foundation

public enum FlexTrackEnvironment: String, Codable, CaseIterable, Sendable {
  case development, testing, staging, production
  public var enableDebug: Bool { self == .development || self == .testing }
  public var enableSampling: Bool { self == .production || self == .staging }
  public var strictConsent: Bool { self == .production }
}

public struct TrackingContext: Sendable, Equatable {
  public let userID: String?
  public let sessionID: String?
  public let deviceID: String?
  public let userProperties: [String: JSONValue]
  public let sessionProperties: [String: JSONValue]
  public let consentManager: ConsentManager
  public let environment: FlexTrackEnvironment
  public let appVersion: String?
  public let buildNumber: String?
  public let createdAt: Date

  public init(
    userID: String? = nil, sessionID: String? = nil, deviceID: String? = nil,
    userProperties: [String: JSONValue] = [:], sessionProperties: [String: JSONValue] = [:],
    consentManager: ConsentManager = ConsentManager(),
    environment: FlexTrackEnvironment = .production,
    appVersion: String? = nil, buildNumber: String? = nil, createdAt: Date = Date()
  ) {
    self.userID = userID; self.sessionID = sessionID; self.deviceID = deviceID
    self.userProperties = userProperties; self.sessionProperties = sessionProperties
    self.consentManager = consentManager; self.environment = environment
    self.appVersion = appVersion; self.buildNumber = buildNumber; self.createdAt = createdAt
  }

  public static func development(
    userID: String? = nil, sessionID: String? = nil,
    consentManager: ConsentManager = ConsentManager()
  ) -> TrackingContext {
    TrackingContext(
      userID: userID, sessionID: sessionID, deviceID: "dev-device",
      consentManager: consentManager, environment: .development,
      appVersion: "dev", buildNumber: "debug")
  }
  public static func testing(userID: String? = nil, sessionID: String? = nil) -> TrackingContext {
    let consent = ConsentManager(); consent.grantAllConsents(version: "test")
    return TrackingContext(
      userID: userID, sessionID: sessionID, deviceID: "test-device",
      consentManager: consent, environment: .testing, appVersion: "test", buildNumber: "0")
  }

  public var isDebugMode: Bool { environment == .development }
  public var isProduction: Bool { environment == .production }
  public var isTesting: Bool { environment == .testing }
  public var isUserIdentified: Bool { !(userID?.isEmpty ?? true) }
  public var hasActiveSession: Bool { !(sessionID?.isEmpty ?? true) }

  public func withUserID(_ value: String?) -> TrackingContext { replacing(userID: value) }
  public func withSessionID(_ value: String?) -> TrackingContext { replacing(sessionID: value) }
  public func withUserProperties(_ values: [String: JSONValue]) -> TrackingContext {
    replacing(userProperties: userProperties.merging(values) { _, new in new })
  }
  public func withSessionProperties(_ values: [String: JSONValue]) -> TrackingContext {
    replacing(sessionProperties: sessionProperties.merging(values) { _, new in new })
  }
  public func withEnvironment(_ value: FlexTrackEnvironment) -> TrackingContext {
    replacing(environment: value)
  }

  public var eventProperties: [String: JSONValue] {
    var values: [String: JSONValue] = [
      "environment": .string(environment.rawValue),
      "context_created_at": .string(createdAt.ISO8601Format()),
    ]
    if let userID { values["user_id"] = .string(userID) }
    if let sessionID { values["session_id"] = .string(sessionID) }
    if let deviceID { values["device_id"] = .string(deviceID) }
    if let appVersion { values["app_version"] = .string(appVersion) }
    if let buildNumber { values["build_number"] = .string(buildNumber) }
    return values
  }

  public func validate() -> [String] {
    var issues = consentManager.validate()
    if isProduction && !isUserIdentified { issues.append("User not identified in production - anonymous tracking") }
    if isProduction && !hasActiveSession { issues.append("No active session in production - session tracking recommended") }
    if isProduction && appVersion == nil { issues.append("App version not set - recommended for production tracking") }
    return issues
  }

  public func encoded() throws -> Data {
    let snapshot = Snapshot(
      userID: userID, sessionID: sessionID, deviceID: deviceID,
      userProperties: userProperties, sessionProperties: sessionProperties,
      consent: consentManager.summary, environment: environment,
      appVersion: appVersion, buildNumber: buildNumber, createdAt: createdAt)
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(snapshot)
  }
  public static func decode(_ data: Data) throws -> TrackingContext {
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let value = try decoder.decode(Snapshot.self, from: data)
    let consent = ConsentManager()
    let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
    try consent.load(encoder.encode(value.consent))
    return TrackingContext(
      userID: value.userID, sessionID: value.sessionID, deviceID: value.deviceID,
      userProperties: value.userProperties, sessionProperties: value.sessionProperties,
      consentManager: consent, environment: value.environment, appVersion: value.appVersion,
      buildNumber: value.buildNumber, createdAt: value.createdAt)
  }

  private func replacing(
    userID: String?? = nil, sessionID: String?? = nil,
    userProperties: [String: JSONValue]? = nil,
    sessionProperties: [String: JSONValue]? = nil,
    environment: FlexTrackEnvironment? = nil
  ) -> TrackingContext {
    TrackingContext(
      userID: userID ?? self.userID, sessionID: sessionID ?? self.sessionID,
      deviceID: deviceID, userProperties: userProperties ?? self.userProperties,
      sessionProperties: sessionProperties ?? self.sessionProperties,
      consentManager: consentManager, environment: environment ?? self.environment,
      appVersion: appVersion, buildNumber: buildNumber, createdAt: createdAt)
  }

  public static func == (lhs: TrackingContext, rhs: TrackingContext) -> Bool {
    lhs.userID == rhs.userID && lhs.sessionID == rhs.sessionID &&
      lhs.deviceID == rhs.deviceID && lhs.environment == rhs.environment
  }

  private struct Snapshot: Codable {
    let userID: String?; let sessionID: String?; let deviceID: String?
    let userProperties: [String: JSONValue]; let sessionProperties: [String: JSONValue]
    let consent: ConsentSummary; let environment: FlexTrackEnvironment
    let appVersion: String?; let buildNumber: String?; let createdAt: Date
  }
}
