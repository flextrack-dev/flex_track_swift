import Foundation
import FlexTrack
import Testing

@testable import FlexTrackSample

struct FlexTrackSampleTests {
  @Test func runtimeStateUsesSafeDefaults() {
    let defaults = isolatedDefaults()
    let state = SampleRuntimeState(defaults: defaults)

    #expect(state.online)
    #expect(state.consent.general)
    #expect(!state.consent.pii)
  }

  @Test func runtimeStatePersistsNetworkAndConsent() {
    let defaults = isolatedDefaults()
    let state = SampleRuntimeState(defaults: defaults)

    state.setOnline(false)
    state.setGeneralConsent(false)
    state.setPIIConsent(true)

    let restored = SampleRuntimeState(defaults: defaults)
    #expect(!restored.online)
    #expect(!restored.consent.general)
    #expect(restored.consent.pii)
  }

  private func isolatedDefaults() -> UserDefaults {
    let suite = "dev.flextrack.sample.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }
}
