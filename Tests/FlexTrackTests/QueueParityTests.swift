import Foundation
import Testing

@testable import FlexTrack

@Suite("Queue parity")
struct QueueParityTests {
  @Test("in-memory queue is idempotent by event ID and preserves FIFO")
  func idempotentFIFO() async throws {
    let queue = InMemoryEventQueue()
    await queue.enqueue(item("one"))
    await queue.enqueue(item("one", trackers: ["archive"]))
    await queue.enqueue(item("two"))
    await queue.enqueue(item("three"))

    #expect(await queue.size() == 3)
    #expect(try await queue.read(limit: 2).map(\.id) == ["one", "two"])
  }

  @Test("replace increments attempts without changing queue position")
  func replaceInPlace() async throws {
    let queue = InMemoryEventQueue()
    await queue.enqueue(item("one", trackers: ["analytics", "archive"]))
    await queue.enqueue(item("two"))

    let first = try #require(try await queue.read(limit: 1).first)
    await queue.replace(first.retrying(["archive"]))
    let result = try await queue.read(limit: 10)

    #expect(result.map(\.id) == ["one", "two"])
    #expect(result.first?.trackerIDs == ["archive"])
    #expect(result.first?.attempts == 1)
  }

  @Test("missing replacement and removal are harmless")
  func missingMutation() async throws {
    let queue = InMemoryEventQueue()
    await queue.enqueue(item("one"))
    await queue.replace(item("missing"))
    await queue.remove(id: "missing")

    #expect(await queue.size() == 1)
    #expect(try await queue.read(limit: 1).first?.id == "one")
  }

  @Test("read rejects zero and negative limits")
  func invalidLimits() async {
    let queue = InMemoryEventQueue()
    await #expect(throws: FlexTrackError.invalidLimit) { try await queue.read(limit: 0) }
    await #expect(throws: FlexTrackError.invalidLimit) { try await queue.read(limit: -1) }
  }

  @Test("clear removes every queued event")
  func clear() async throws {
    let queue = InMemoryEventQueue()
    await queue.enqueue(item("one"))
    await queue.enqueue(item("two"))
    await queue.clear()
    #expect(await queue.size() == 0)
  }

  @Test("file queue persists replace, remove, and clear")
  func fileMutationsPersist() async throws {
    let location = temporaryQueueURL()
    defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
    let queue = try FileEventQueue(fileURL: location)
    try await queue.enqueue(item("one", trackers: ["analytics", "archive"]))
    try await queue.enqueue(item("two"))
    let first = try #require(try await queue.read(limit: 1).first)
    try await queue.replace(first.retrying(["archive"]))
    try await queue.remove(id: "two")

    var restored = try FileEventQueue(fileURL: location)
    var values = try await restored.read(limit: 10)
    #expect(values.map(\.id) == ["one"])
    #expect(values.first?.attempts == 1)
    #expect(values.first?.trackerIDs == ["archive"])

    try await restored.clear()
    restored = try FileEventQueue(fileURL: location)
    values = try await restored.read(limit: 10)
    #expect(values.isEmpty)
  }

  @Test("file queue rejects corrupted persistence instead of losing data silently")
  func corruptedFile() throws {
    let location = temporaryQueueURL()
    defer { try? FileManager.default.removeItem(at: location.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(
      at: location.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("not-json".utf8).write(to: location)

    #expect(throws: (any Error).self) { try FileEventQueue(fileURL: location) }
  }

  private func item(_ id: String, trackers: [String] = ["analytics"]) -> QueuedEvent {
    QueuedEvent(
      event: FlexEvent(id: id, name: "purchase", requiresConsent: false),
      trackerIDs: trackers)
  }

  private func temporaryQueueURL() -> URL {
    FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString)
      .appendingPathComponent("queue.json")
  }
}
