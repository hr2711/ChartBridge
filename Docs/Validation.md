# Versioned baseline through Objective 16

The initial Git baseline includes the SwiftUI foundation/design system, domain verification, JPEG/PNG/single-page PDF import, on-device OCR/simple-chart extraction, editable evidence review, deterministic insights, optional on-device explanation with deterministic fallback, speech/exploration, local verified library, reports, reliability hardening and UI polish.

## Pre-commit validation

- XC-MCP generic iOS Simulator Debug build passed: zero errors, one AppIntents metadata-skipped warning, no Swift 6 concurrency diagnostics. Build ID: ce80f548-416a-4477-abc0-6b4f7bf931c6.
- `swift test --filter 'Chart(ImportSafety|Reliability|Library|Report|Insights|Accessibility)Tests'`: 33 Swift Testing tests across six suites passed, zero failures.
- The malformed-PDF rejection test intentionally emits a CoreGraphics diagnostic. It passed.
- Xcode project plist lint passed.
- One UI assertion was aligned to the current import-verification guidance using a stable accessibility identifier; the assertion still checks the complete guidance text. UI tests were not executed in this pre-commit pass.

No simulator boot, launch, interaction, screenshots or accessibility scans were performed in this pass. Earlier synthetic extraction measurements are recorded separately in ExtractionAccuracy.md and are not a fresh runtime certification.

## Known limitations

The existing SwiftUI “Invalid frame dimension (negative or non-finite)” runtime warning remains unresolved; source inspection did not establish a safe fix. Real VoiceOver/speech timing, AX5/appearance layout after the latest polish, sharing behavior, device memory/performance and protected-file behavior while locked still require runtime validation. Extraction supports only the documented simple-chart scope; all extracted candidates require explicit human confirmation. PDF/UA compliance is not certified.

## Source-control privacy

Generated chart documents and imported files, build/test output, logs, archives, credentials, local documents and machine-specific XC-MCP configuration are ignored. Synthetic fixture source/generator code is versioned instead of binary documents. Local historical reports containing workstation paths/account-session details are preserved but excluded. No remote is invented when one is absent; setting up the intended ChartBridge GitHub remote is a separate user-directed action.
