import Foundation
import Testing

@testable import FlexTrack

@Suite("Client parity")
struct ClientParityTests {
  @Test("tracking before startup fails without queueing")
  func requiresStartup() async throws {
    let queue = InMemoryEventQueue()
    let client = client(queue: queue)

    await #expect(throws: FlexTrackError.clientNotStarted) {
      try await client.track(testEvent())
    }
    #expect(await queue.size() == 0)
  }

  @Test("offline event with no routing targets is not queued")
  func offlineNoTarget() async throws {
    let queue = InMemoryEventQueue()
    let client = client(queue: queue, online: false)
    try await client.register(ClientTracker(id: "unrelated"))
    try await client.start()

    let result = try await client.track(testEvent())

    #expect(result.routing.targetTrackerIDs.isEmpty)
    #expect(result.queuedTrackerIDs.isEmpty)
    #expect(await queue.size() == 0)
  }

  @Test("all-success dispatch keeps the queue empty and preserves result ordering")
  func allSuccess() async throws {
    let queue = InMemoryEventQueue()
    let client = client(queue: queue)
    let first = ClientTracker(id: "analytics", delay: 20_000_000)
    let second = ClientTracker(id: "archive")
    try await client.register(first)
    try await client.register(second)
    try await client.start()

    let result = try await client.track(testEvent())

    #expect(result.successfulTrackerIDs == ["analytics", "archive"])
    #expect(result.failures.isEmpty)
    #expect(result.queuedTrackerIDs.isEmpty)
    #expect(await queue.size() == 0)
  }

  @Test("transformers run in registration order and dispatch the final snapshot")
  func transformerOrder() async throws {
    let tracker = ClientTracker(id: "analytics")
    let client = client(targets: ["analytics"])
    try await client.register(tracker)
    await client.addTransformer { $0.enriched(with: ["order": .string("first")]) }
    await client.addTransformer { event in
      let previous = event.properties["order"] ?? .null
      return event.enriched(with: ["previous": previous, "order": .string("second")])
    }
    try await client.start()

    let result = try await client.track(testEvent())

    #expect(result.event.properties["order"] == .string("second"))
    #expect(result.event.properties["previous"] == .string("first"))
    #expect(await tracker.lastEvent == result.event)
  }

  @Test("transformer failure prevents routing, delivery, and queueing")
  func transformerFailure() async throws {
    let queue = InMemoryEventQueue()
    let tracker = ClientTracker(id: "analytics")
    let client = client(targets: ["analytics"], queue: queue)
    try await client.register(tracker)
    await client.addTransformer { _ in throw ClientFailure.transformer }
    try await client.start()

    await #expect(throws: ClientFailure.transformer) { try await client.track(testEvent()) }
    #expect(await tracker.count == 0)
    #expect(await queue.size() == 0)
  }

  @Test("flush limit processes only the oldest queued events")
  func flushLimit() async throws {
    let queue = InMemoryEventQueue()
    for id in ["one", "two", "three"] {
      await queue.enqueue(QueuedEvent(event: testEvent(id: id), trackerIDs: ["analytics"]))
    }
    let tracker = ClientTracker(id: "analytics")
    let client = client(targets: ["analytics"], queue: queue)
    try await client.register(tracker)
    try await client.start()

    let result = try await client.flush(limit: 2)

    #expect(result == FlushResult(attemptedEvents: 2, deliveredEvents: 2, remainingEvents: 1))
    #expect(await tracker.eventIDs == ["one", "two"])
    #expect(try await queue.read(limit: 10).map(\.id) == ["three"])
  }

  @Test("failed flush retains only failures and increments attempts once")
  func failedFlush() async throws {
    let queue = InMemoryEventQueue()
    await queue.enqueue(
      QueuedEvent(event: testEvent(), trackerIDs: ["analytics", "archive"]))
    let success = ClientTracker(id: "analytics")
    let failure = ClientTracker(id: "archive", failures: 1)
    let client = client(queue: queue)
    try await client.register(success)
    try await client.register(failure)
    try await client.start()

    let result = try await client.flush()
    let remaining = try #require(try await queue.read(limit: 10).first)

    #expect(result == FlushResult(attemptedEvents: 1, deliveredEvents: 0, remainingEvents: 1))
    #expect(remaining.trackerIDs == ["archive"])
    #expect(remaining.attempts == 1)
    #expect(await success.count == 1)
  }

  @Test("flush rejects invalid limits before reading the queue")
  func invalidFlushLimit() async {
    let client = client()
    await #expect(throws: FlexTrackError.invalidLimit) { try await client.flush(limit: 0) }
  }

  private func client(
    targets: [String] = ["analytics", "archive"],
    queue: any EventQueue = InMemoryEventQueue(),
    online: Bool = true
  ) -> FlexTrackClient {
    FlexTrackClient(
      routingEngine: RoutingEngine(
        RoutingConfiguration(rules: [
          RoutingRule(
            targetGroup: TrackerGroup("all", trackerIDs: targets),
            nameContains: "purchase", requireConsent: false)
        ])),
      queue: queue,
      onlineProvider: { online })
  }

  private func testEvent(id: String = "event-1") -> FlexEvent {
    FlexEvent(id: id, name: "purchase", requiresConsent: false)
  }
}

private actor ClientTracker: Tracker {
  nonisolated let id: String
  private var failures: Int
  private let delay: UInt64
  private var events: [FlexEvent] = []

  init(id: String, failures: Int = 0, delay: UInt64 = 0) {
    self.id = id
    self.failures = failures
    self.delay = delay
  }

  var count: Int { events.count }
  var lastEvent: FlexEvent? { events.last }
  var eventIDs: [String] { events.map(\.id) }

  func track(_ event: FlexEvent) async throws {
    events.append(event)
    if delay > 0 { try await Task.sleep(nanoseconds: delay) }
    if failures > 0 {
      failures -= 1
      throw ClientFailure.delivery
    }
  }
}

private enum ClientFailure: Error { case transformer, delivery }
