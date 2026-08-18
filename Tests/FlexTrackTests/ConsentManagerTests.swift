import Foundation
import Testing

@testable import FlexTrack

@Suite("Flutter-parity consent manager")
struct ConsentManagerTests {
  private let now = Date(timeIntervalSince1970: 1_776_384_000)
  private func manager() -> ConsentManager { ConsentManager(now: { now }) }

  @Test("initial state is privacy safe")
  func initial() {
    let value = manager()
    #expect(!value.hasAnyConsent && !value.hasAllConsents)
    #expect(value.consentTimestamp == nil && value.consentVersion == nil)
    #expect(ConsentType.allCases.allSatisfy { !value.isAllowed(for: $0) })
  }

  @Test("each standard consent changes independently", arguments: ConsentType.allCases)
  func individual(type: ConsentType) {
    let value = manager(); value.set(type, granted: true)
    #expect(value.isAllowed(for: type)); #expect(value.consentTimestamp == now)
    #expect(ConsentType.allCases.filter { $0 != type }.allSatisfy { !value.isAllowed(for: $0) })
  }

  @Test("bulk updates preserve unspecified values")
  func bulk() {
    let value = manager()
    value.setConsents(general: true, pii: true, version: "1.0")
    value.setConsents(general: false, marketing: true, version: "1.1")
    #expect(!value.hasGeneralConsent && value.hasPIIConsent && value.hasMarketingConsent)
    #expect(value.consentVersion == "1.1")
  }

  @Test("grant and revoke all include custom lifecycle")
  func all() throws {
    let value = manager(); value.grantAllConsents(version: "2")
    try value.setCustomConsent("location", granted: true)
    #expect(value.hasAllConsents && value.customConsent(for: "location"))
    value.revokeAllConsents()
    #expect(!value.hasAnyConsent && value.customConsents.isEmpty)
  }

  @Test("custom consent returns snapshots and supports removal")
  func custom() throws {
    let value = manager(); try value.setCustomConsent("camera", granted: true)
    var snapshot = value.customConsents; snapshot["camera"] = false
    #expect(value.customConsent(for: "camera")); #expect(!value.customConsent(for: "missing"))
    value.removeCustomConsent("camera"); #expect(!value.customConsent(for: "camera"))
  }

  @Test("blank custom purpose and version fail")
  func invalidMetadata() {
    #expect(throws: FlexTrackConfigurationError.empty("consent purpose")) {
      try manager().setCustomConsent(" ", granted: true)
    }
    #expect(throws: FlexTrackConfigurationError.empty("consent version")) {
      try manager().setConsentVersion("")
    }
  }

  @Test("required is inverse of allowed")
  func required() {
    let value = manager(); value.setAnalyticsConsent(true)
    #expect(ConsentType.allCases.allSatisfy {
      value.isConsentRequired(for: $0) == !value.isAllowed(for: $0)
    })
  }

  @Test("summary remains an immutable compliance snapshot")
  func snapshot() throws {
    let value = manager(); value.setGeneralConsent(true)
    try value.setCustomConsent("location", granted: true); try value.setConsentVersion("1")
    let snapshot = value.summary; value.setGeneralConsent(false)
    #expect(snapshot.general && snapshot.hasAnyConsent && !snapshot.hasAllStandardConsents)
    #expect(snapshot.version == "1" && snapshot.custom["location"] == true)
  }

  @Test("routing state exposes general and PII")
  func routingState() {
    let value = manager(); value.setGeneralConsent(true); value.setMarketingConsent(true)
    #expect(value.summary.routingState == ConsentState(general: true, pii: false))
  }

  @Test("encoded state round trips completely")
  func coding() throws {
    let original = manager(); original.setConsents(general: true, analytics: true, version: "v2")
    try original.setCustomConsent("camera", granted: true)
    let restored = manager(); try restored.load(original.encoded())
    #expect(restored.summary == original.summary)
  }

  @Test("malformed encoded state fails instead of silently granting consent")
  func malformed() {
    let value = manager(); value.grantAllConsents()
    #expect(throws: (any Error).self) { try value.load(Data("bad".utf8)) }
    #expect(value.hasAllConsents)
  }

  @Test("validation warns about general without PII and missing version")
  func validation() {
    let value = manager(); value.setGeneralConsent(true)
    #expect(value.validate().contains { $0.contains("PII consent denied") })
    #expect(value.validate().contains { $0.contains("Consent version not set") })
    #expect(!value.validate().contains { $0.contains("timestamp not set") })
  }
}
