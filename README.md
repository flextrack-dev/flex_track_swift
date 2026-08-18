# FlexTrack Swift

Consent-aware, deterministic analytics routing for Swift and Apple platforms.
This package is the Swift implementation of the same versioned Core and Runtime
contracts used by FlexTrack Flutter and Kotlin.

## Requirements

- Swift 6.2+
- iOS 15+
- macOS 12+

## Installation

Add this repository in Xcode with **File → Add Package Dependencies**, then
import the library:

```swift
import FlexTrack
```

## Basic usage

```swift
let tracker = MyTracker()
let client = try await FlexTrackBuilder()
    .tracker(tracker)
    .consent { ConsentState(general: true) }
    .debugLogging()
    .routing {
        try $0.defineGroup("product", trackerIDs: [tracker.id])
            .routeNamed("purchase") {
                try $0.toGroup(named: "product").id("purchase-route")
            }
            .routeDefault { $0.toAll() }
    }
    .build()

let result = try await client.track(
    FlexEvent(
        name: "purchase_completed",
        properties: ["plan": .string("pro")]
    )
)
```

Use a dynamic tracking context when versioned consent and user/session
enrichment should be configured together:

```swift
let consent = ConsentManager()
consent.setConsents(general: true, analytics: true, version: "2026-08")
let context = TrackingContext(
    userID: "user-42",
    sessionID: "session-7",
    consentManager: consent
)

let client = try await FlexTrackBuilder()
    .tracker(MyTracker())
    .trackingContext { context }
    .routing { try $0.routeDefault { $0.toAll() } }
    .build()
```

`Tracker` implementations are isolated from each other. Failed destinations
are queued without retrying destinations that already succeeded.

## Offline delivery

Use `FileEventQueue` for process-safe restoration and provide connectivity from
the host application:

```swift
let queue = try FileEventQueue(
    fileURL: applicationSupportURL.appendingPathComponent("flextrack-queue.json")
)
let client = try await FlexTrackBuilder()
    .tracker(MyTracker())
    .queue(queue)
    .network { networkMonitor.isOnline }
    .routing { try $0.routeDefault { $0.toAll() } }
    .build()
```

Offline events retain their identity, timestamp, transformed properties, and
pending tracker IDs. Call `try await client.flush()` after connectivity returns.

## Privacy defaults

`ConsentState()` denies general and PII consent. Applications must explicitly
grant the appropriate consent. Essential events may bypass general-consent and
sampling checks, but never bypass a required PII-consent check.

## Shared contract

The language-neutral specifications and fixtures are vendored in `Contract/`.
Changes to routing or runtime delivery must remain compatible with those files.

## Public utilities

`PatternMatcher`, `SamplingUtils`, and `ValidationUtils` provide the public
Flutter-equivalent helpers with Swift-native types. Seeded random sampling is
reproducible and deterministic sampling uses the shared FNV-1a contract.

### Test trackers and health diagnostics

Use the `RecordingTracker` actor (also available as `MockTracker`) in package
or integration tests, and `NoOpTracker` when a configured destination must
intentionally discard events. `events()` returns a value snapshot and `reset()`
clears captured events.

Every tracker declares `TrackerCapabilities`; `tracker.diagnostics()` and
`registry.diagnostics()` expose typed lifecycle and delivery-count snapshots
for developer tooling without logging event payloads.
