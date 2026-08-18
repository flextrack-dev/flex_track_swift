# Changelog

All notable changes to FlexTrack Swift are documented in this file.

## 1.1.0 - 2026-08-18

Initial public Swift Package release, aligned with the Kotlin SDK version and
the shared FlexTrack Core and Runtime specifications.

### Added

- Swift-native fluent configuration and client builders.
- Immutable events with stable identifiers, timestamps, privacy metadata, and
  typed JSON properties.
- Consent-aware routing with priorities, deterministic sampling, named tracker
  groups, categories, and detailed routing diagnostics.
- Smart, GDPR, CCPA, privacy-region, and performance routing presets.
- Versioned consent management and dynamic user/session tracking context.
- Actor-safe tracker registry with isolated lifecycle and delivery failures.
- Durable offline event queue, selective per-destination retry, FIFO recovery,
  and serialized flush operations.
- Ordered event transformer pipeline.
- Public pattern matching, sampling, and validation utilities.
- Actor-based `RecordingTracker`/`MockTracker` and `NoOpTracker` implementations.
- Typed tracker capabilities, lifecycle diagnostics, error categories, and
  stable failure codes.
- SwiftUI sample application with developer console diagnostics.
- Vendored cross-SDK specifications and deterministic conformance fixtures.
- 134 package tests across 15 suites.

### Compatibility

- Requires Swift 6.2 or later.
- Supports iOS 15 or later and macOS 12 or later.
- Distributed as the `FlexTrack` Swift Package product.
- Core Specification remains `1.0.0`; Runtime Specification remains `1.0.0`.

### License

- Released under the MIT License.
