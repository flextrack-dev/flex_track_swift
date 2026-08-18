# Cross-SDK test parity

Updated: 2026-08-18

This matrix compares behavior, not raw test counts. A row is **covered** only when the SDK has an executable test for the behavior. “Feature gap” means the production API does not exist yet, so adding a test alone would be misleading.

| Behavior | Flutter | Kotlin | Swift | Next action |
|---|---|---|---|---|
| Stable event identity and timestamp | Covered | Covered | Covered | Keep in shared contract |
| Metadata-preserving enrichment | Covered | Covered | Covered | Keep in shared contract |
| Nested property serialization | Covered | Partial: uses `Any?` | Covered: typed `JSONValue` | Define cross-SDK property limits |
| Deterministic sampling and boundaries | Covered | Covered | Covered | Add more shared vectors |
| Priority and same-tier routing | Covered | Covered | Covered | Keep in shared contract |
| Default routing fallback | Covered | Covered | Covered | Keep in shared contract |
| General and PII consent | Covered | Covered | Covered | Add essential-event fixture |
| Essential event bypass | Covered | Covered | Covered after parity fix | Add shared fixture |
| Missing tracker diagnostics | Covered | Covered | Covered after parity fix | Standardize warning text |
| Regex/property/type routing | Covered | Covered | Feature gap | Design Swift rule predicates |
| Debug/production-only rules | Covered | Covered | Feature gap | Design Swift environment input |
| Routing presets/builders | Covered | Feature gap | Feature gap | Port only after core parity |
| Offline queue-all | Covered | Covered | Covered | Keep in shared runtime contract |
| Duplicate queue ID idempotency | Covered | Covered | Covered | Keep in shared runtime contract |
| FIFO, limit, replace, attempts | Covered | Covered | Covered | Extend runtime fixtures |
| Durable queue restoration | Covered | Covered on device | Covered | Add platform corruption fixtures |
| Corrupted queue behavior | Covered | Covered on device | Covered | Standardize recovery policy |
| Partial delivery retry | Covered | Covered | Covered | Keep in shared runtime contract |
| Retry avoids successful targets | Covered | Covered | Covered | Keep in shared runtime contract |
| Concurrent flush deduplication | Covered | Covered | Covered | Keep as stress test |
| Tracker lifecycle idempotency | Covered | Covered | Covered | Extend lifecycle fixtures |
| Startup rollback | Covered | Covered | Covered | Standardize tracker ordering |
| Transformer order/failure | Covered | Covered | Covered | Decide failure isolation contract |
| Library debug logging policy | Covered | Covered | Feature gap; sample logger only | Add opt-in Swift logger API |
| Flutter inspector/widgets | Covered | Not applicable | Not applicable | Test native sample UI instead |
| Sample state persistence | Covered | Covered | Covered | Add offline relaunch UI test |
| Provider adapters | Covered/varies | Feature gap | Feature gap | Implement after core contract |

## Current executable inventory

- Flutter: 855 declared tests across 54 test files. Its production surface is about 9,458 lines.
- Kotlin: 62 statically declared tests after this parity pass, plus dynamic shared-contract cases and Android instrumentation tests.
- Swift: 44 package tests after this parity pass, plus sample unit/UI tests.
- Shared contract: 8 Core MVP cases and 11 Runtime MVP cases.

Raw totals are not a release gate. The gate is that every implemented cross-SDK behavior has the same observable result, while platform-specific behavior has its own focused tests.

## Release gates

1. All shared fixture cases pass unchanged in every SDK.
2. Offline and partial-failure paths never lose an event silently.
3. Retry never redelivers a successful destination.
4. Consent and sampling defaults remain privacy-safe.
5. Durable queues survive process restart and reject corrupt state explicitly.
6. Public logging is disabled or privacy-safe by default in release builds.
7. Every fixed parity bug receives a regression test before release.
