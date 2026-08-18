import Foundation
import Testing

@testable import FlexTrack

@Suite("Runtime delivery contract")
struct RuntimeTests {
  @Test("offline dispatch queues all targets without invoking trackers")
  func offlineQueue() async throws {
    let first = RecordingTracker(id: "analytics")
    let second = RecordingTracker(id: "archive")
    let client = makeClient(online: false)
    try await client.register(first)
    try await client.register(second)
    try await client.start()

    let result = try await client.track(event())

    #expect(result.queuedTrackerIDs == ["analytics", "archive"])
    #expect(await first.count == 0)
    #expect(await second.count == 0)
    #expect(await client.queue.size() == 1)
  }

  @Test("partial failure queues only failed destinations")
  func partialFailure() async throws {
    let success = RecordingTracker(id: "analytics")
    let failure = RecordingTracker(id: "archive", failuresRemaining: 1)
    let client = makeClient()
    try await client.register(success)
    try await client.register(failure)
    try await client.start()

    let result = try await client.track(event())

    #expect(result.successfulTrackerIDs == ["analytics"])
    #expect(result.queuedTrackerIDs == ["archive"])
    #expect(await client.queue.size() == 1)
  }

  @Test("retry uses transformed snapshot and never redelivers successful targets")
  func selectiveRetry() async throws {
    let success = RecordingTracker(id: "analytics")
    let retry = RecordingTracker(id: "archive", failuresRemaining: 1)
    let transforms = Counter()
    let client = makeClient()
    try await client.register(success)
    try await client.register(retry)
    await client.addTransformer { original in
      transforms.increment()
      return original.enriched(with: ["transform": .string("once")])
    }
    try await client.start()

    _ = try await client.track(event())
    let flush = try await client.flush()

    #expect(flush.deliveredEvents == 1)
    #expect(transforms.value == 1)
    #expect(await success.count == 1)
    #expect(await retry.count == 2)
    #expect(await retry.lastEvent?.properties["transform"] == .string("once"))
  }

  @Test("offline flush is a complete no-op")
  func offlineFlush() async throws {
    let queue = InMemoryEventQueue()
    await queue.enqueue(QueuedEvent(event: event(), trackerIDs: ["analytics"]))
    let client = makeClient(online: false, queue: queue)
    try await client.register(RecordingTracker(id: "analytics"))
    try await client.start()

    let result = try await client.flush()

    #expect(result == FlushResult(attemptedEvents: 0, deliveredEvents: 0, remainingEvents: 1))
  }

  @Test("concurrent flush calls never duplicate queued delivery")
  func concurrentFlush() async throws {
    let queue = InMemoryEventQueue()
    await queue.enqueue(QueuedEvent(event: event(), trackerIDs: ["analytics"]))
    let tracker = RecordingTracker(id: "analytics", delayNanoseconds: 50_000_000)
    let client = makeClient(queue: queue)
    try await client.register(tracker)
    try await client.start()

    async let first = client.flush()
    async let second = client.flush()
    let results = try await [first, second]

    #expect(results.map(\.attemptedEvents).sorted() == [0, 1])
    #expect(await tracker.count == 1)
    #expect(await queue.size() == 0)
  }

  @Test("file queue restores FIFO state and event identity")
  func fileQueueRestoration() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url = directory.appendingPathComponent("queue.json")
    defer { try? FileManager.default.removeItem(at: directory) }
    let first = try FileEventQueue(fileURL: url)
    try await first.enqueue(QueuedEvent(event: event(id: "event-1"), trackerIDs: ["analytics"]))
    try await first.enqueue(QueuedEvent(event: event(id: "event-2"), trackerIDs: ["archive"]))

    let restored = try FileEventQueue(fileURL: url)
    let values = try await restored.read(limit: 10)

    #expect(values.map(\.id) == ["event-1", "event-2"])
    #expect(values.first?.event.id == "event-1")
  }
}

private func makeClient(
  online: Bool = true,
  queue: any EventQueue = InMemoryEventQueue()
) -> FlexTrackClient {
  FlexTrackClient(
    routingEngine: RoutingEngine(
      RoutingConfiguration(rules: [
        RoutingRule(
          targetGroup: TrackerGroup("all", trackerIDs: ["analytics", "archive"]),
          nameContains: "purchase",
          requireConsent: false
        )
      ])),
    queue: queue,
    onlineProvider: { online }
  )
}

private func event(id: String = "event-1") -> FlexEvent {
  FlexEvent(id: id, name: "purchase", properties: ["plan": .string("pro")], requiresConsent: false)
}

private actor RecordingTracker: Tracker {
  nonisolated let id: String
  private var failuresRemaining: Int
  private let delayNanoseconds: UInt64
  private var events: [FlexEvent] = []

  init(id: String, failuresRemaining: Int = 0, delayNanoseconds: UInt64 = 0) {
    self.id = id
    self.failuresRemaining = failuresRemaining
    self.delayNanoseconds = delayNanoseconds
  }

  var count: Int { events.count }
  var lastEvent: FlexEvent? { events.last }

  func track(_ event: FlexEvent) async throws {
    events.append(event)
    if delayNanoseconds > 0 {
      try await Task.sleep(nanoseconds: delayNanoseconds)
    }
    if failuresRemaining > 0 {
      failuresRemaining -= 1
      throw TestFailure.expected
    }
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var storage = 0
  var value: Int { lock.withLock { storage } }
  func increment() { lock.withLock { storage += 1 } }
}

private enum TestFailure: Error { case expected }
