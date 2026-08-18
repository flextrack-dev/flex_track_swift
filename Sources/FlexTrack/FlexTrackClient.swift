import Foundation

public struct TrackerFailure: @unchecked Sendable {
  public let trackerID: String
  public let error: any Error
}

public struct DispatchResult: Sendable {
  public let event: FlexEvent
  public let routing: RoutingResult
  public let successfulTrackerIDs: [String]
  public let failures: [TrackerFailure]
  public let queuedTrackerIDs: [String]
}

public struct FlushResult: Sendable, Equatable {
  public let attemptedEvents: Int
  public let deliveredEvents: Int
  public let remainingEvents: Int
}

public actor FlexTrackClient {
  public let routingEngine: RoutingEngine
  public let registry: TrackerRegistry
  public let queue: any EventQueue
  private let consentProvider: @Sendable () -> ConsentState
  private let onlineProvider: @Sendable () -> Bool
  private let logger: FlexTrackLogger
  private var transformers: [EventTransformer] = []
  private var started = false
  private var flushing = false
  private var flushWaiters: [CheckedContinuation<Void, Never>] = []

  public init(
    routingEngine: RoutingEngine,
    registry: TrackerRegistry = TrackerRegistry(),
    queue: any EventQueue = InMemoryEventQueue(),
    consentProvider: @escaping @Sendable () -> ConsentState = { ConsentState() },
    onlineProvider: @escaping @Sendable () -> Bool = { true },
    logger: FlexTrackLogger = .disabled
  ) {
    self.routingEngine = routingEngine
    self.registry = registry
    self.queue = queue
    self.consentProvider = consentProvider
    self.onlineProvider = onlineProvider
    self.logger = logger
  }

  public func register(_ tracker: any Tracker) async throws {
    try await registry.register(tracker)
  }

  public func addTransformer(_ transformer: @escaping EventTransformer) {
    transformers.append(transformer)
  }

  public func start() async throws {
    try await registry.start()
    started = true
  }

  public func shutdown() async {
    await registry.shutdown()
    started = false
  }

  public func track(_ event: FlexEvent) async throws -> DispatchResult {
    guard started else { throw FlexTrackError.clientNotStarted }
    var processed = event
    for transformer in transformers { processed = try transformer(processed) }
    let trackers = await registry.snapshot()
    let routing = routingEngine.route(
      processed,
      consent: consentProvider(),
      availableTrackerIDs: Set(trackers.keys)
    )
    let targets = routing.targetTrackerIDs
    logger.log("🟣 ROUTE \(processed.name) targets=\(targets) properties=\(processed.properties)")
    if !onlineProvider(), !targets.isEmpty {
      try await queue.enqueue(QueuedEvent(event: processed, trackerIDs: targets))
      logger.log("🟠 QUEUED \(processed.name) targets=\(targets) reason=offline")
      return DispatchResult(
        event: processed,
        routing: routing,
        successfulTrackerIDs: [],
        failures: [],
        queuedTrackerIDs: targets
      )
    }
    let outcomes = await deliver(processed, to: targets, trackers: trackers)
    let successes = outcomes.compactMap { $0.error == nil ? $0.trackerID : nil }
    let failures = outcomes.compactMap { outcome in
      outcome.error.map { TrackerFailure(trackerID: outcome.trackerID, error: $0) }
    }
    let failedIDs = failures.map(\.trackerID)
    if !failedIDs.isEmpty {
      try await queue.enqueue(QueuedEvent(event: processed, trackerIDs: failedIDs))
      logger.log("🟠 QUEUED \(processed.name) targets=\(failedIDs) reason=delivery_failure")
    }
    return DispatchResult(
      event: processed,
      routing: routing,
      successfulTrackerIDs: successes,
      failures: failures,
      queuedTrackerIDs: failedIDs
    )
  }

  public func flush(limit: Int = 100) async throws -> FlushResult {
    guard limit > 0 else { throw FlexTrackError.invalidLimit }
    await acquireFlushLock()
    defer { releaseFlushLock() }
    guard onlineProvider() else {
      logger.log("⚪ OFFLINE flush skipped")
      return FlushResult(
        attemptedEvents: 0, deliveredEvents: 0, remainingEvents: await queue.size())
    }
    let items = try await queue.read(limit: limit)
    let trackers = await registry.snapshot()
    var deliveredEvents = 0
    for item in items {
      let outcomes = await deliver(item.event, to: item.trackerIDs, trackers: trackers)
      let failedIDs = outcomes.compactMap { $0.error == nil ? nil : $0.trackerID }
      if failedIDs.isEmpty {
        try await queue.remove(id: item.id)
        deliveredEvents += 1
      } else {
        try await queue.replace(item.retrying(failedIDs))
      }
    }
    return FlushResult(
      attemptedEvents: items.count,
      deliveredEvents: deliveredEvents,
      remainingEvents: await queue.size()
    )
  }

  private func acquireFlushLock() async {
    if !flushing {
      flushing = true
      return
    }
    await withCheckedContinuation { continuation in flushWaiters.append(continuation) }
    flushing = true
  }

  private func releaseFlushLock() {
    flushing = false
    if !flushWaiters.isEmpty { flushWaiters.removeFirst().resume() }
  }

  private struct Outcome: @unchecked Sendable {
    let index: Int
    let trackerID: String
    let error: (any Error)?
  }

  private func deliver(
    _ event: FlexEvent,
    to trackerIDs: [String],
    trackers: [String: any Tracker]
  ) async -> [Outcome] {
    let deliveryLogger = logger
    return await withTaskGroup(of: Outcome.self) { group in
      for (index, trackerID) in trackerIDs.enumerated() {
        group.addTask {
          guard let tracker = trackers[trackerID] else {
            return Outcome(
              index: index, trackerID: trackerID,
              error: FlexTrackError.trackerUnavailable(trackerID))
          }
          do {
            try await tracker.track(event)
            deliveryLogger.log("🟢 DELIVER \(event.name) target=\(trackerID)")
            return Outcome(index: index, trackerID: trackerID, error: nil)
          } catch {
            deliveryLogger.log("🔴 FAILED \(event.name) target=\(trackerID) error=\(error)")
            return Outcome(index: index, trackerID: trackerID, error: error)
          }
        }
      }
      var outcomes: [Outcome] = []
      for await outcome in group { outcomes.append(outcome) }
      return outcomes.sorted { $0.index < $1.index }
    }
  }
}
