import FlexTrack
import Combine
import Foundation
import OSLog

@MainActor
final class SampleViewModel: ObservableObject {
  #if DEBUG
    private static let console = Logger(
      subsystem: Bundle.main.bundleIdentifier ?? "dev.flextrack.sample",
      category: "FlexTrack"
    )
  #endif

  @Published private(set) var logs: [SampleLog] = []
  @Published private(set) var queueCount = 0
  @Published private(set) var sentCount = 0
  @Published private(set) var isReady = false
  @Published private(set) var isBusy = false
  @Published var isOnline: Bool {
    didSet {
      runtime.setOnline(isOnline)
      Task { await refreshQueue() }
    }
  }
  @Published var generalConsent: Bool { didSet { runtime.setGeneralConsent(generalConsent) } }
  @Published var piiConsent: Bool { didSet { runtime.setPIIConsent(piiConsent) } }

  let runtime: SampleRuntimeState
  private let tracker: SampleTracker
  private let client: FlexTrackClient

  init(runtime: SampleRuntimeState = SampleRuntimeState()) {
    self.runtime = runtime
    self.isOnline = runtime.online
    self.generalConsent = runtime.consent.general
    self.piiConsent = runtime.consent.pii
    self.tracker = SampleTracker()

    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first!
    let queueURL = support.appendingPathComponent("FlexTrackSample/flextrack-queue.json")
    let queue: any EventQueue
    if let durableQueue = try? FileEventQueue(fileURL: queueURL) {
      queue = durableQueue
    } else {
      queue = InMemoryEventQueue()
    }
    let state = runtime
    self.client = FlexTrackClient(
      routingEngine: RoutingEngine(
        RoutingConfiguration(rules: [
          RoutingRule(
            id: "sample-default",
            targetGroup: TrackerGroup("sample", trackerIDs: ["sample_tracker"]),
            isDefault: true, requireConsent: true
          )
        ])
      ),
      queue: queue,
      consentProvider: { state.consent },
      onlineProvider: { state.online }
    )
  }

  func start() async {
    guard !isReady else { return }
    do {
      try await client.register(tracker)
      try await client.start()
      isReady = true
      debugLog("🟢 READY tracker=sample_tracker queue=FileEventQueue")
      await refreshQueue()
    } catch {
      append(.error, event: "startup", message: String(describing: error))
    }
  }

  func track(_ template: EventTemplate) async {
    guard isReady, !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    let event = FlexEvent(name: template.id, properties: template.properties)
    do {
      let result = try await client.track(event)
      sentCount += 1
      append(
        .routed, event: event.name, message: "targets=\(result.routing.targetTrackerIDs)",
        properties: event.properties)
      if result.queuedTrackerIDs.isEmpty {
        append(
          .delivered, event: event.name, message: "trackers=\(result.successfulTrackerIDs)",
          properties: event.properties)
      } else {
        append(
          .queued, event: event.name, message: "pending=\(result.queuedTrackerIDs)",
          properties: event.properties)
      }
    } catch {
      append(
        .error, event: event.name, message: String(describing: error), properties: event.properties)
    }
    await refreshQueue()
  }

  func flush() async {
    guard isReady, !isBusy else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      let result = try await client.flush()
      append(
        .flush, event: "queue",
        message:
          "attempted=\(result.attemptedEvents) delivered=\(result.deliveredEvents) remaining=\(result.remainingEvents)"
      )
    } catch {
      append(.error, event: "flush", message: String(describing: error))
    }
    await refreshQueue()
  }

  func clearLogs() { logs.removeAll() }
  func refreshQueue() async { queueCount = await client.queue.size() }

  private func append(
    _ kind: SampleLog.Kind, event: String, message: String, properties: [String: JSONValue] = [:]
  ) {
    let propertiesText = Self.render(properties)
    debugLog(
      "\(Self.symbol(for: kind)) \(kind.rawValue) \(event) \(message) properties=\(propertiesText)"
    )
    logs.insert(
      SampleLog(kind: kind, eventName: event, message: message, properties: properties), at: 0)
  }

  private func debugLog(_ message: String) {
    #if DEBUG
      Self.console.debug("\(message, privacy: .public)")
    #endif
  }

  private static func render(_ properties: [String: JSONValue]) -> String {
    guard !properties.isEmpty else { return "{}" }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard
      let data = try? encoder.encode(properties),
      let value = String(data: data, encoding: .utf8)
    else { return String(describing: properties) }
    return value
  }

  private static func symbol(for kind: SampleLog.Kind) -> String {
    switch kind {
    case .routed: "🟣"
    case .delivered: "🟢"
    case .queued: "🟠"
    case .flush: "🔵"
    case .error: "🔴"
    }
  }
}
