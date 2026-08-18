import Foundation

public struct QueuedEvent: Sendable, Codable, Equatable {
  public let id: String
  public let event: FlexEvent
  public let trackerIDs: [String]
  public let attempts: Int
  public let queuedAt: Date

  public init(
    id: String? = nil,
    event: FlexEvent,
    trackerIDs: [String],
    attempts: Int = 0,
    queuedAt: Date = Date()
  ) {
    precondition(!trackerIDs.isEmpty, "queued tracker ids cannot be empty")
    precondition(attempts >= 0, "attempts cannot be negative")
    self.id = id ?? event.id
    self.event = event
    self.trackerIDs = trackerIDs.reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    self.attempts = attempts
    self.queuedAt = queuedAt
  }

  public func retrying(_ trackerIDs: [String]) -> QueuedEvent {
    QueuedEvent(
      id: id,
      event: event,
      trackerIDs: trackerIDs,
      attempts: attempts + 1,
      queuedAt: queuedAt
    )
  }
}

public protocol EventQueue: Sendable {
  func enqueue(_ item: QueuedEvent) async throws
  func read(limit: Int) async throws -> [QueuedEvent]
  func replace(_ item: QueuedEvent) async throws
  func remove(id: String) async throws
  func size() async -> Int
  func clear() async throws
}

public actor InMemoryEventQueue: EventQueue {
  private var items: [QueuedEvent] = []

  public init() {}

  public func enqueue(_ item: QueuedEvent) {
    guard !items.contains(where: { $0.id == item.id }) else { return }
    items.append(item)
  }

  public func read(limit: Int) throws -> [QueuedEvent] {
    guard limit > 0 else { throw FlexTrackError.invalidLimit }
    return Array(items.prefix(limit))
  }

  public func replace(_ item: QueuedEvent) {
    guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
    items[index] = item
  }

  public func remove(id: String) { items.removeAll { $0.id == id } }
  public func size() -> Int { items.count }
  public func clear() { items.removeAll() }
}
