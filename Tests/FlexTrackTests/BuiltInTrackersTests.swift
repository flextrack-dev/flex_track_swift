import Testing

@testable import FlexTrack

@Suite("Built-in trackers and diagnostics")
struct BuiltInTrackersTests {
  @Test("recording tracker captures ordered events and returns snapshots")
  func recording() async throws {
    let tracker = RecordingTracker()
    let first = FlexEvent(name: "first")
    let second = FlexEvent(name: "second")
    try await tracker.track(first); try await tracker.track(second)
    #expect(await tracker.events() == [first, second])
  }

  @Test("mock discovery name and reset clear captured events")
  func reset() async throws {
    let tracker = MockTracker()
    try await tracker.track(FlexEvent(name: "first")); await tracker.reset()
    #expect(await tracker.events().isEmpty)
  }

  @Test("recording diagnostics expose lifecycle counts and capabilities")
  func recordingDiagnostics() async throws {
    let capabilities = TrackerCapabilities(
      supportsBatchTracking: true, maxBatchSize: 50, isGDPRCompliant: true
    )
    let tracker = RecordingTracker(id: "test", displayName: "Test tracker", capabilities: capabilities)
    try await tracker.start(); try await tracker.track(FlexEvent(name: "event")); await tracker.shutdown()
    let value = await tracker.diagnostics()
    #expect(value.lifecycleState == .shutdown)
    #expect(value.trackedEventCount == 1 && value.startCount == 1 && value.shutdownCount == 1)
    #expect(value.capabilities == capabilities)
  }

  @Test("no-op tracker discards payloads but reports delivery count")
  func noOp() async throws {
    let tracker = NoOpTracker()
    try await tracker.start(); try await tracker.track(FlexEvent(name: "secret")); await tracker.shutdown()
    let value = await tracker.diagnostics()
    #expect(value.trackedEventCount == 1 && value.lifecycleState == .shutdown)
  }

  @Test("registry aggregates diagnostics by stable tracker ID")
  func registry() async throws {
    let first = RecordingTracker(id: "first")
    let second = NoOpTracker(id: "second")
    let registry = TrackerRegistry()
    try await registry.register(first); try await registry.register(second)
    try await first.track(FlexEvent(name: "event"))
    let values = await registry.diagnostics()
    #expect(Set(values.keys) == Set(["first", "second"]))
    #expect(values["first"]?.trackedEventCount == 1)
  }

  @Test("default diagnostics preserve existing tracker compatibility")
  func compatibility() async {
    let value = await LegacyTracker().diagnostics()
    #expect(value.displayName == "legacy" && value.lifecycleState == nil)
  }
}

private struct LegacyTracker: Tracker {
  let id = "legacy"
  func track(_ event: FlexEvent) async throws {}
}
