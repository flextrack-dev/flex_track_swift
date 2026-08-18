import Foundation

public protocol Tracker: Sendable {
  var id: String { get }
  var displayName: String { get }
  var capabilities: TrackerCapabilities { get }
  func start() async throws
  func track(_ event: FlexEvent) async throws
  func flush() async throws
  func shutdown() async
  func diagnostics() async -> TrackerDiagnostics
}

extension Tracker {
  public var displayName: String { id }
  public var capabilities: TrackerCapabilities { TrackerCapabilities() }
  public func start() async throws {}
  public func flush() async throws {}
  public func shutdown() async {}
  public func diagnostics() async -> TrackerDiagnostics {
    TrackerDiagnostics(id: id, displayName: displayName, capabilities: capabilities)
  }
}

public struct TrackerCapabilities: Sendable, Equatable {
  public let supportsBatchTracking: Bool
  public let supportsRealtimeTracking: Bool
  public let maxBatchSize: Int
  public let isGDPRCompliant: Bool

  public init(
    supportsBatchTracking: Bool = false,
    supportsRealtimeTracking: Bool = true,
    maxBatchSize: Int = 1,
    isGDPRCompliant: Bool = false
  ) {
    precondition(maxBatchSize > 0, "maxBatchSize must be greater than zero")
    self.supportsBatchTracking = supportsBatchTracking
    self.supportsRealtimeTracking = supportsRealtimeTracking
    self.maxBatchSize = maxBatchSize
    self.isGDPRCompliant = isGDPRCompliant
  }
}

public enum TrackerLifecycleState: String, Sendable, Equatable {
  case created, started, shutdown
}

public struct TrackerDiagnostics: Sendable, Equatable {
  public let id: String
  public let displayName: String
  public let capabilities: TrackerCapabilities
  public let lifecycleState: TrackerLifecycleState?
  public let trackedEventCount: Int?
  public let startCount: Int?
  public let shutdownCount: Int?

  public init(
    id: String,
    displayName: String,
    capabilities: TrackerCapabilities,
    lifecycleState: TrackerLifecycleState? = nil,
    trackedEventCount: Int? = nil,
    startCount: Int? = nil,
    shutdownCount: Int? = nil
  ) {
    self.id = id
    self.displayName = displayName
    self.capabilities = capabilities
    self.lifecycleState = lifecycleState
    self.trackedEventCount = trackedEventCount
    self.startCount = startCount
    self.shutdownCount = shutdownCount
  }
}

public actor TrackerRegistry {
  private var trackers: [String: any Tracker] = [:]
  private var started = false

  public init() {}

  public func register(_ tracker: any Tracker) throws {
    guard !tracker.id.isEmpty else { throw FlexTrackError.invalidTrackerID }
    guard trackers[tracker.id] == nil else { throw FlexTrackError.duplicateTracker(tracker.id) }
    guard !started else { throw FlexTrackError.registryAlreadyStarted }
    trackers[tracker.id] = tracker
  }

  @discardableResult
  public func unregister(_ id: String) -> (any Tracker)? {
    guard !started else { return nil }
    return trackers.removeValue(forKey: id)
  }

  public func start() async throws {
    if started { return }
    var initialized: [any Tracker] = []
    do {
      for tracker in trackers.values {
        try await tracker.start()
        initialized.append(tracker)
      }
      started = true
    } catch {
      for tracker in initialized { await tracker.shutdown() }
      throw error
    }
  }

  public func shutdown() async {
    guard started else { return }
    for tracker in trackers.values { await tracker.shutdown() }
    started = false
  }

  public func snapshot() -> [String: any Tracker] { trackers }

  public func diagnostics() async -> [String: TrackerDiagnostics] {
    var result: [String: TrackerDiagnostics] = [:]
    for (id, tracker) in trackers { result[id] = await tracker.diagnostics() }
    return result
  }
}

public enum FlexTrackError: Error, Equatable {
  case invalidTrackerID
  case duplicateTracker(String)
  case registryAlreadyStarted
  case trackerUnavailable(String)
  case clientNotStarted
  case invalidLimit
}
