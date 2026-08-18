import Foundation
import Testing

@testable import FlexTrack

@Suite("Flutter-parity tracking context")
struct TrackingContextTests {
  private let now = Date(timeIntervalSince1970: 1_776_384_000)

  @Test("basic context uses production privacy defaults")
  func basic() {
    let context = TrackingContext(createdAt: now)
    #expect(context.environment == .production)
    #expect(!context.isUserIdentified && !context.hasActiveSession)
    #expect(!context.consentManager.hasAnyConsent && context.createdAt == now)
  }

  @Test("all initializer data is retained")
  func complete() {
    let context = TrackingContext(
      userID: "user", sessionID: "session", deviceID: "device",
      userProperties: ["plan": .string("pro")], sessionProperties: ["source": .string("direct")],
      environment: .staging, appVersion: "1", buildNumber: "2", createdAt: now)
    #expect(context.userProperties["plan"] == .string("pro"))
    #expect(context.sessionProperties["source"] == .string("direct"))
    #expect(context.environment == .staging)
  }

  @Test("development factory has debug metadata")
  func development() {
    let context = TrackingContext.development(userID: "user", sessionID: "session")
    #expect(context.deviceID == "dev-device" && context.appVersion == "dev")
    #expect(context.isDebugMode && !context.isProduction)
  }

  @Test("testing factory grants all versioned consents")
  func testing() {
    let context = TrackingContext.testing(userID: "user", sessionID: "session")
    #expect(context.isTesting && context.consentManager.hasAllConsents)
    #expect(context.consentManager.consentVersion == "test")
  }

  @Test("environment capabilities mirror Flutter")
  func environments() {
    #expect(FlexTrackEnvironment.development.enableDebug && FlexTrackEnvironment.testing.enableDebug)
    #expect(FlexTrackEnvironment.staging.enableSampling && FlexTrackEnvironment.production.enableSampling)
    #expect(FlexTrackEnvironment.production.strictConsent && !FlexTrackEnvironment.staging.strictConsent)
  }

  @Test("identity updates create independent values")
  func identityUpdates() {
    let original = TrackingContext(userID: "one", sessionID: "first", createdAt: now)
    let updated = original.withUserID("two").withSessionID("second")
    #expect(original.userID == "one" && original.sessionID == "first")
    #expect(updated.userID == "two" && updated.sessionID == "second")
  }

  @Test("property updates merge without mutation")
  func propertyUpdates() {
    let original = TrackingContext(
      userProperties: ["age": .number(25), "plan": .string("basic")],
      sessionProperties: ["page": .number(1)], createdAt: now)
    let updated = original
      .withUserProperties(["age": .number(26), "premium": .bool(true)])
      .withSessionProperties(["page": .number(2)])
    #expect(original.userProperties["age"] == .number(25))
    #expect(updated.userProperties["age"] == .number(26))
    #expect(updated.userProperties["premium"] == .bool(true))
    #expect(updated.sessionProperties["page"] == .number(2))
  }

  @Test("event properties contain only non-null context fields")
  func eventProperties() {
    let context = TrackingContext(
      userID: "user", deviceID: "device", environment: .staging,
      appVersion: "1", createdAt: now)
    #expect(context.eventProperties["user_id"] == .string("user"))
    #expect(context.eventProperties["device_id"] == .string("device"))
    #expect(context.eventProperties["session_id"] == nil)
    #expect(context.eventProperties["environment"] == .string("staging"))
  }

  @Test("encoded context round trips public state and consent")
  func coding() throws {
    let consent = ConsentManager(now: { now }); consent.setConsents(general: true, version: "1")
    let original = TrackingContext(
      userID: "user", sessionID: "session", deviceID: "device",
      userProperties: ["age": .number(25)], sessionProperties: ["source": .string("search")],
      consentManager: consent, environment: .staging, appVersion: "2", buildNumber: "20", createdAt: now)
    let restored = try TrackingContext.decode(original.encoded())
    #expect(restored == original && restored.userProperties == original.userProperties)
    #expect(restored.consentManager.hasGeneralConsent && restored.consentManager.consentVersion == "1")
  }

  @Test("production validation reports identity session version and consent")
  func validation() {
    let consent = ConsentManager(); consent.setGeneralConsent(true)
    let issues = TrackingContext(consentManager: consent, createdAt: now).validate()
    #expect(issues.contains { $0.contains("User not identified") })
    #expect(issues.contains { $0.contains("No active session") })
    #expect(issues.contains { $0.contains("App version not set") })
    #expect(issues.contains { $0.contains("Consent version not set") })
  }

  @Test("complete production context validates cleanly")
  func validProduction() {
    let consent = ConsentManager(now: { now }); consent.grantAllConsents(version: "1")
    #expect(TrackingContext(
      userID: "user", sessionID: "session", consentManager: consent,
      appVersion: "1", createdAt: now).validate().isEmpty)
  }

  @Test("equality follows Flutter routing identity fields")
  func equality() {
    let first = TrackingContext(
      userID: "user", sessionID: "session", deviceID: "device",
      userProperties: ["a": .number(1)], environment: .development, createdAt: now)
    let same = TrackingContext(
      userID: "user", sessionID: "session", deviceID: "device",
      userProperties: ["a": .number(2)], environment: .development, createdAt: now)
    #expect(first == same); #expect(first != first.withEnvironment(.production))
  }
}
