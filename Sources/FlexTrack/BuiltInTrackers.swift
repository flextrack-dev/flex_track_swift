import Foundation

/// A production-safe sink that intentionally discards events while exposing lifecycle diagnostics.
public actor NoOpTracker: Tracker {
  public nonisolated let id: String
  public nonisolated let displayName: String
  private var state: TrackerLifecycleState = .created
  private var starts = 0
  private var shutdowns = 0
  private var tracked = 0

  public init(id: String = "noop", displayName: String = "No-op tracker") {
    precondition(!id.isEmpty, "tracker id cannot be empty")
    self.id = id
    self.displayName = displayName
  }

  public func start() async throws { starts += 1; state = .started }
  public func track(_ event: FlexEvent) async throws { tracked += 1 }
  public func shutdown() async { shutdowns += 1; state = .shutdown }
  public func diagnostics() async -> TrackerDiagnostics {
    TrackerDiagnostics(
      id: id, displayName: displayName, capabilities: capabilities,
      lifecycleState: state, trackedEventCount: tracked,
      startCount: starts, shutdownCount: shutdowns
    )
  }
}

/// In-memory tracker for deterministic package tests, examples, and local integration debugging.
public actor RecordingTracker: Tracker {
  public nonisolated let id: String
  public nonisolated let displayName: String
  public nonisolated let capabilities: TrackerCapabilities
  private var captured: [FlexEvent] = []
  private var state: TrackerLifecycleState = .created
  private var starts = 0
  private var shutdowns = 0

  public init(
    id: String = "recording",
    displayName: String = "Recording tracker",
    capabilities: TrackerCapabilities = TrackerCapabilities()
  ) {
    precondition(!id.isEmpty, "tracker id cannot be empty")
    self.id = id
    self.displayName = displayName
    self.capabilities = capabilities
  }

  public func start() async throws { starts += 1; state = .started }
  public func track(_ event: FlexEvent) async throws { captured.append(event) }
  public func shutdown() async { shutdowns += 1; state = .shutdown }
  public func events() -> [FlexEvent] { captured }
  public func reset() { captured.removeAll(keepingCapacity: true) }
  public func diagnostics() async -> TrackerDiagnostics {
    TrackerDiagnostics(
      id: id, displayName: displayName, capabilities: capabilities,
      lifecycleState: state, trackedEventCount: captured.count,
      startCount: starts, shutdownCount: shutdowns
    )
  }
}

public typealias MockTracker = RecordingTracker
