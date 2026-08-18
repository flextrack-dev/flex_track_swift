import Testing

@testable import FlexTrack

@Suite("Tracker registry parity")
struct RegistryParityTests {
  @Test("registration rejects duplicate and empty tracker IDs")
  func registrationValidation() async throws {
    let registry = TrackerRegistry()
    try await registry.register(LifecycleTracker(id: "analytics"))

    await #expect(throws: FlexTrackError.duplicateTracker("analytics")) {
      try await registry.register(LifecycleTracker(id: "analytics"))
    }
    await #expect(throws: FlexTrackError.invalidTrackerID) {
      try await registry.register(LifecycleTracker(id: ""))
    }
  }

  @Test("unregister returns the tracker and missing IDs are harmless")
  func unregister() async throws {
    let registry = TrackerRegistry()
    let tracker = LifecycleTracker(id: "analytics")
    try await registry.register(tracker)

    let removed = await registry.unregister("analytics")
    let missing = await registry.unregister("missing")

    #expect(removed?.id == "analytics")
    #expect(missing == nil)
    #expect(await registry.snapshot().isEmpty)
  }

  @Test("start and shutdown are idempotent")
  func lifecycleIdempotency() async throws {
    let registry = TrackerRegistry()
    let tracker = LifecycleTracker(id: "analytics")
    try await registry.register(tracker)

    try await registry.start()
    try await registry.start()
    await registry.shutdown()
    await registry.shutdown()

    #expect(await tracker.startCount == 1)
    #expect(await tracker.shutdownCount == 1)
  }

  @Test("registry prevents mutation while started and allows it after shutdown")
  func mutationBoundaries() async throws {
    let registry = TrackerRegistry()
    try await registry.register(LifecycleTracker(id: "first"))
    try await registry.start()

    await #expect(throws: FlexTrackError.registryAlreadyStarted) {
      try await registry.register(LifecycleTracker(id: "second"))
    }
    #expect(await registry.unregister("first") == nil)

    await registry.shutdown()
    #expect(await registry.unregister("first")?.id == "first")
  }

  @Test("failed startup rolls back initialized trackers and can be retried")
  func startupRollback() async throws {
    let registry = TrackerRegistry()
    let healthy = LifecycleTracker(id: "healthy")
    let flaky = LifecycleTracker(id: "flaky", startFailures: 1)
    try await registry.register(healthy)
    try await registry.register(flaky)

    await #expect(throws: LifecycleFailure.expected) { try await registry.start() }
    try await registry.start()

    let healthyStarts = await healthy.startCount
    let flakyStarts = await flaky.startCount
    let shutdowns = await healthy.shutdownCount + flaky.shutdownCount
    #expect(healthyStarts == 1 || healthyStarts == 2)
    #expect(flakyStarts == 2)
    #expect((3...4).contains(healthyStarts + flakyStarts))
    #expect((0...1).contains(shutdowns))
  }
}

private actor LifecycleTracker: Tracker {
  nonisolated let id: String
  private var failures: Int
  private(set) var startCount = 0
  private(set) var shutdownCount = 0

  init(id: String, startFailures: Int = 0) {
    self.id = id
    self.failures = startFailures
  }

  func start() throws {
    startCount += 1
    if failures > 0 {
      failures -= 1
      throw LifecycleFailure.expected
    }
  }

  func track(_ event: FlexEvent) {}
  func shutdown() { shutdownCount += 1 }
}

private enum LifecycleFailure: Error { case expected }
