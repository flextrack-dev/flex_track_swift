# FlexTrack cross-SDK capability matrix

Flutter is the product reference. `Equivalent` means the observable behavior is
covered by a shared or mirrored package test. `Adapted` means the capability is
present through a platform-idiomatic API. `Missing` is scheduled work and must
not be described as full parity.

| Public capability | Kotlin | Swift | Notes |
|---|---|---|---|
| Event identity, timestamp, metadata | Equivalent | Equivalent | Immutable native models |
| Deterministic sampling | Equivalent | Equivalent | Shared fixture coverage |
| Routing conditions and priority | Equivalent | Equivalent | Native DSL/fluent API |
| Configuration/client builder | Adapted | Adapted | Kotlin DSL; Swift fluent async builder |
| Smart routing presets and variants | Equivalent | Equivalent | Mirrored rule/priority/rate tests |
| GDPR/CCPA presets and regions | Equivalent | Equivalent | Named compliant destination groups |
| Performance presets and variants | Equivalent | Equivalent | Mobile/web/server/throughput variants |
| Configuration validation | Equivalent | Equivalent | Native typed construction prevents invalid rates |
| Routing diagnostic snapshot | Adapted | Adapted | Logcat/debug objects; Swift debug objects |
| Offline durable queue and selective retry | Equivalent | Equivalent | Process restoration covered |
| Transformer ordering and failure isolation | Equivalent | Equivalent | Runtime package tests |
| Tracker registry and lifecycle | Equivalent | Equivalent | Platform concurrency primitives |
| Consent manager with five consent purposes | Equivalent | Equivalent | Thread-safe native snapshots; general + PII feed routing |
| Tracking context enrichment | Equivalent | Equivalent | Immutable context with dynamic builder integration |
| Pattern matching utility surface | Equivalent | Equivalent | Wildcards, properties, categories, bounded regex cache |
| Sampling utility surface | Equivalent | Equivalent | Native seed correctly reseeds random generator |
| Validation utility surface | Equivalent | Equivalent | Native DTOs preserve platform type safety |
| Built-in mock/no-op trackers | Equivalent | Equivalent | Thread-safe recording and no-op implementations |
| Tracker capability diagnostics | Equivalent | Equivalent | Typed capability and lifecycle snapshots; registry aggregation |
| Global convenience facade | Adapted | Adapted | DI/client ownership preferred on Native |
| Visual inspector | Adapted | Adapted | Sample UI + Logcat/console, not library widgets |
| Flutter tracking widgets | Not applicable | Not applicable | Native UI integration is platform-specific |
| Typed public failure model | Adapted | Adapted | Kotlin exception hierarchy; exhaustive Swift errors with stable categories/codes |

## Gate

A row can move to `Equivalent` or `Adapted` only with package-level tests. Sample
and UI tests do not count. Intentional omissions require an explicit rationale in
this document.
