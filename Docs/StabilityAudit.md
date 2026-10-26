# ChartBridge stability audit

Scope: the existing app after Ask Your Chart. No new chart support, dependencies,
network processing, screens, or design changes. The starting working tree was
clean on `main`; no Git remote was configured.

## Audit checklist and evidence

- [x] Launch/navigation/onboarding: inspected app composition, tab/path state,
  sample navigation and dismissal. Existing host navigation/onboarding tests pass.
- [x] Imports: inspected bounded file reads, security-scoped access and release,
  actual ImageIO type validation, pixel limits, encrypted/empty/multipage PDF
  rejection, orientation normalization and cancellation. Added rotated-PDF coverage.
- [x] OCR/extraction: reviewed Vision configuration, top-left bounds, strict OCR
  number parsing, linear calibration, label association, bar baselines, line marker
  requirements, radial pie sampling and uncertainty. Existing fictional samples
  exercise real Vision and geometry for all four supported chart kinds on the Mac.
  No algorithm changes or expanded support were justified by those results.
- [x] Verification/calculations/visual data: inspected explicit confirmation,
  edit invalidation, Decimal arithmetic, baseline policy, ties, pie percentage
  points, ordered line observations and display-only rounding. Strengthened stale
  checks and made comparison-unit normalization consistent.
- [x] Apple Intelligence: reviewed compile/OS/runtime checks, bounded fact-ID
  selection, deterministic fallback and cancellation. Test providers exercise
  unavailable, invalid, failed and cancelled outcomes; no live model was invoked.
- [x] Ask Your Chart: reviewed bounded grammar, exact normalized category matching,
  positive percentage baselines, chart-kind restrictions, memory-only history,
  bounded worker cache and full-snapshot late-answer rejection. Existing focused
  tests cover these paths; underlying comparison-unit fix also covers its answers.
- [x] Speech/accessibility: reviewed request identities, interruption handling,
  VoiceOver separation, native controls, semantic typography and frame arguments.
  Added full-snapshot speech invalidation; host tests do not establish audio or UI
  accessibility correctness on iOS.
- [x] Storage: reviewed canonical/checksummed records, validation on reopen,
  atomic protected writes, corruption retention, leaf/root symlink rejection,
  digest-based update/delete, duplicate-save behavior and cancellation. Added a
  capacity guard; existing saving/security/corruption tests remain passing.
- [x] Reports/sharing: reviewed source-data exclusion, delivery authorization,
  cancellation, bounded PDF pagination and system-managed DataRepresentation
  exports. No app-owned export temporary files are created. Plain-text transfer
  now avoids PDF generation entirely.
- [ ] Runtime-only validation: no simulator launch, Xcode GUI interaction, UI
  tests, screenshots, real VoiceOver speech, AX5 layout or device measurements.

## Confirmed defects and smallest fixes

| Priority | Root cause and evidence | Fix / regression coverage |
| --- | --- | --- |
| High: verified-data integrity | Several derived-content consumers compared only ID/revision. Independently edited copies can share both while holding different values. A regression obtained old report bytes under authorization for different data. Insights/explorer freshness had the same failure. | Bind insights, explanations, report payloads and speech content/state to the full immutable snapshot. Validate at report delivery, speech start, async explanation publication and UI authorization changes. Same-key/different-data tests cover report, explanation, explorer, speech and existing question history. |
| High: import accuracy | Rotated single-page PDFs used unrotated bitmap dimensions. Synthetic 90/270-degree pages lost half their colored content, risking incomplete OCR. | Size by page rotation and use Quartz's documented page transform once, with explicit bounded render scaling. Tests check 0/90/180/270 degrees, nonzero MediaBox origin, dimensions and greater than 98% filled synthetic page coverage. |
| Medium: missing-unit presentation | General insights trimmed unit whitespace, but pairwise comparisons did not. A confirmed “Not specified” marker appeared verbatim in Ask Your Chart answers. | One normalized unit helper for both paths. Regression verifies the typed unit and the exact answer without invented units. |
| Medium: storage availability | Listing rejects more than 2,000 JSON records, but insertion had no matching bound. Successful saves could therefore make the library unreadable. | Enforce the same capacity before a new write. A capacity regression preserves the original, permits idempotent saves and rejects an extra copy without creating its file. |
| Efficiency / export reliability | Plain-text transfer always performed CoreText pagination and generated unused PDF bytes, inheriting PDF-only rendering failures and work. | A text-only preparation path exits before font/layout/PDF creation. Regression proves identical text and no PDF allocation, and refuses a PDF delivery request from that text-only payload. No wall-clock speedup is claimed. |

Initial regression execution failed on the unit, stale-data and rotated-PDF
cases before their fixes. The first PDF repair still failed pixel-coverage
assertions; correcting the logical-to-bitmap scale resolved them. Tests were not
weakened to accept clipping.

## Remaining risks, ranked

1. **High release-validation gap, not a newly confirmed defect:** run physical-device
   VoiceOver, AX5, keyboard/Switch Control and interrupted import/save/export flows.
   The Mac tests and generic SDK build cannot prove those runtime behaviors.
2. **Medium unresolved runtime warning:** the previously reported invalid SwiftUI
   frame warning was not reproduced in this no-simulator pass. Source review found
   fixed positive sizes, flexible maximum widths and a positive scaled chart height;
   no evidence identifies the offending runtime frame. Capture its call stack and
   exact navigation/text-size state next session; do not claim it fixed.
3. **Medium recognition limitation:** synthetic samples are not a real-world OCR
   accuracy benchmark. Grouped/stacked/multi-series, markerless lines and unlabeled
   pies remain unsupported. All extracted estimates still require human review.
4. **Low hardening / concurrency follow-up:** filesystem checks and optimistic
   digests assume the existing single app-owned library actor, not hostile concurrent
   writers changing ancestor paths. UI refresh-versus-write ordering deserves a
   controlled iOS lifecycle test; no data loss was demonstrated here. No speculative
   locking, caching framework or filesystem rewrite was introduced.

No end-to-end speed, memory, energy or PDF/UA compliance claim is made. The PDF
transform follows [Apple's Core Graphics documentation](https://developer.apple.com/documentation/coregraphics/cgpdfpage/getdrawingtransform(_:rect:rotate:preserveaspectratio:)).

## Final validation

- `swift test`: **83 Swift Testing tests in 11 suites passed**, including the five
  added regression tests (PDF rotation is parameterized over four orientations).
  The XCTest runner's preceding “0 tests” message is not the Swift Testing result.
- One consolidated XC-MCP Debug build for `generic/platform=iOS Simulator`:
  **passed**, zero errors, build ID `f7429edf-35c2-4327-9883-09d8c4ecc0ba`.
- Swift 6 strict concurrency remains enabled; no Swift compiler diagnostics were
  reported. The build's one warning is AppIntents metadata extraction being skipped
  because the app has no AppIntents framework dependency.
- The intentionally malformed PDF rejection fixture emits a CoreGraphics PDF
  diagnostic on the host. Its rejection assertion passes; it is not a valid-file
  failure or a suppressed test issue.
- `git diff --check` passes. No simulator or GUI was operated in this pass. Real
  model sessions and iOS-only UI automation suites were not run.
