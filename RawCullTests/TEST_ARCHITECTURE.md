# RawCull Test Architecture

RawCull tests use the Swift Testing framework. The suite is intended to stay
small enough to run regularly and strict enough that passing tests represent
real application behavior, not test-framework setup checks.

## Test Categories

- Smoke tests: fast deterministic checks selected by `make test-smoke`.
- Full tests: all test files with Thread Sanitizer enabled through `make test-full`.
- Performance / stress tests: long-running thread-safety stress checks selected by
  `make test-performance`.

## Quality Bar

- Tests should assert RawCull behavior or state transitions directly.
- Manual diagnostics, local-path RAW-file probes, templates, and console-only checks
  do not belong in the automated target.
- Placeholder assertions such as `#expect(true)` should be removed or replaced with
  assertions against production APIs.
- Shared state tests should use isolated temporary caches/settings unless they are
  deliberately exercising the singleton under Thread Sanitizer.
- Unit tests should target parser, math, cache, concurrency, persistence, and
  view-model behavior. Pure SwiftUI rendering/layout, the `RawCullApp` entry
  point, simple display-only models, and live process integrations belong outside
  this unit target unless they gain meaningful business logic.

## Current Focus Areas

- RAW metadata parsers using synthetic fixture data.
- Thumbnail request/cache behavior, cancellation, and loader concurrency bounds.
- Sharpness and similarity scoring numeric behavior.
- View-model navigation, zoom overlay, and security-scoped path behavior.
- TSan-oriented stress tests for RawCull shared cache state.
