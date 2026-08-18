import Foundation

public protocol Tracker: Sendable {
  var id: String { get }
  func start() async throws
  func track(_ event: FlexEvent) async throws
  func flush() async throws
  func shutdown() async
}

extension Tracker {
  public func start() async throws {}
  public func flush() async throws {}
  public func shutdown() async {}
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
}

public enum FlexTrackError: Error, Equatable {
  case invalidTrackerID
  case duplicateTracker(String)
  case registryAlreadyStarted
  case trackerUnavailable(String)
  case clientNotStarted
  case invalidLimit
}
