import FlexTrack
import Foundation
import SwiftUI

enum FlexPalette {
  static let canvas = Color(red: 0.035, green: 0.055, blue: 0.10)
  static let panel = Color(red: 0.075, green: 0.105, blue: 0.17)
  static let signal = Color(red: 0.20, green: 0.84, blue: 0.91)
  static let violet = Color(red: 0.52, green: 0.43, blue: 0.96)
  static let success = Color(red: 0.30, green: 0.86, blue: 0.55)
  static let warning = Color(red: 1.0, green: 0.69, blue: 0.25)
}

struct SampleLog: Identifiable, Equatable {
  enum Kind: String {
    case routed = "ROUTE"
    case delivered = "DELIVERED"
    case queued = "QUEUED"
    case flush = "FLUSH"
    case error = "ERROR"
  }
  let id = UUID()
  let timestamp = Date()
  let kind: Kind
  let eventName: String
  let message: String
  let properties: [String: JSONValue]
}

struct EventTemplate: Identifiable {
  let id: String
  let title: String
  let description: String
  let symbol: String
  let properties: [String: JSONValue]

  static let samples = [
    EventTemplate(
      id: "basic_event", title: "Basic event", description: "Verify the shortest delivery path.",
      symbol: "sparkles", properties: ["surface": .string("ios_sample")]
    ),
    EventTemplate(
      id: "add_to_cart", title: "Add to cart", description: "Send typed commerce context.",
      symbol: "cart.fill",
      properties: [
        "product_id": .string("coffee-42"), "price": .number(12.5), "currency": .string("EUR"),
      ]
    ),
    EventTemplate(
      id: "handled_error", title: "Handled error",
      description: "Inspect safe diagnostic properties.",
      symbol: "exclamationmark.triangle.fill",
      properties: ["type": .string("sample_error"), "handled": .bool(true)]
    ),
  ]
}

final class SampleRuntimeState: @unchecked Sendable {
  private let lock = NSLock()
  private let defaults: UserDefaults
  private var onlineStorage: Bool
  private var generalConsentStorage: Bool
  private var piiConsentStorage: Bool

  nonisolated init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    self.onlineStorage = defaults.object(forKey: "sample.online") as? Bool ?? true
    self.generalConsentStorage = defaults.object(forKey: "sample.generalConsent") as? Bool ?? true
    self.piiConsentStorage = defaults.object(forKey: "sample.piiConsent") as? Bool ?? false
  }

  nonisolated var online: Bool { lock.withLock { onlineStorage } }
  nonisolated var consent: ConsentState {
    lock.withLock { ConsentState(general: generalConsentStorage, pii: piiConsentStorage) }
  }

  nonisolated func setOnline(_ value: Bool) {
    lock.withLock { onlineStorage = value }
    defaults.set(value, forKey: "sample.online")
  }

  nonisolated func setGeneralConsent(_ value: Bool) {
    lock.withLock { generalConsentStorage = value }
    defaults.set(value, forKey: "sample.generalConsent")
  }

  nonisolated func setPIIConsent(_ value: Bool) {
    lock.withLock { piiConsentStorage = value }
    defaults.set(value, forKey: "sample.piiConsent")
  }
}

actor SampleTracker: Tracker {
  nonisolated let id = "sample_tracker"
  private(set) var events: [FlexEvent] = []
  func track(_ event: FlexEvent) async throws { events.append(event) }
}
