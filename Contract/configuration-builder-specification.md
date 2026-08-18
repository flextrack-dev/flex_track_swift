# FlexTrack Configuration Builder Contract 1.0

Flutter is the reference implementation. Native SDKs use language-idiomatic
syntax, while the resulting routing and runtime behavior remains equivalent.

## Routing builder

A conforming builder supports named and predefined groups; substring, regular
expression, exact name, category, property, PII, high-volume, essential, and
default conditions; direct and group targets; sampling shortcuts at 1%, 10%,
50%, and 100%; consent, PII consent, environment, priority, ID, and description
modifiers; global switches; stable descending priority; and an automatic
all-trackers fallback at priority `-1000`.

Empty names and targets, unknown references, invalid sampling rates, and empty
metadata fail during configuration.

## Client builder

One builder configures tracker registration, routing, ordered transformers,
consent and connectivity providers, offline queue, debug logging, and optional
automatic startup. Its result must remain equivalent to manual construction.

## Package-test gate

Builder tests belong to the publishable library test target. Sample and UI tests
do not count. Native SDKs test each behavior above against Flutter semantics.
