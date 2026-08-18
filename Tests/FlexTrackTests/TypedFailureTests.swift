import Testing

@testable import FlexTrack

@Suite("Typed public failure model")
struct TypedFailureTests {
  @Test("runtime failures expose stable categories and codes")
  func runtime() {
    let values: [(FlexTrackError, FlexTrackFailureCategory, String)] = [
      (.invalidTrackerID, .tracker, "INVALID_TRACKER_ID"),
      (.duplicateTracker("analytics"), .tracker, "DUPLICATE_TRACKER"),
      (.registryAlreadyStarted, .lifecycle, "REGISTRY_ALREADY_STARTED"),
      (.trackerUnavailable("analytics"), .tracker, "TRACKER_UNAVAILABLE"),
      (.clientNotStarted, .lifecycle, "CLIENT_NOT_STARTED"),
      (.invalidLimit, .queue, "INVALID_LIMIT"),
    ]
    for (error, category, code) in values {
      #expect(error.category == category && error.code == code)
    }
  }

  @Test("configuration failures remain exhaustive native enum values")
  func configuration() {
    let error = FlexTrackConfigurationError.invalidSamplingRate(2)
    #expect(error.category == .configuration)
    #expect(error.code == "INVALID_SAMPLING_RATE")
  }
}
