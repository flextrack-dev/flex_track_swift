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
let routing = RoutingEngine(
    RoutingConfiguration(rules: [
        RoutingRule(
            id: "default",
            targetGroup: TrackerGroup("analytics", trackerIDs: [tracker.id]),
            nameContains: "purchase",
            requireConsent: true
        )
    ])
)

let client = FlexTrackClient(
    routingEngine: routing,
    consentProvider: { ConsentState(general: true) }
)
try await client.register(tracker)
try await client.start()

let result = try await client.track(
    FlexEvent(
        name: "purchase_completed",
        properties: ["plan": .string("pro")]
    )
)
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
let client = FlexTrackClient(
    routingEngine: routing,
    queue: queue,
    onlineProvider: { networkMonitor.isOnline }
)
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
