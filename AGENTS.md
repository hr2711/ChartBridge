# ChartBridge Engineering Instructions

## Scope and priorities

These instructions apply to the entire ChartBridge repository. Build ChartBridge as a production-quality, accessibility-first native SwiftUI iPhone application. In priority order: protect user data and existing work, preserve factual correctness, provide accessible behavior, maintain deterministic results, verify changes, and optimize only with evidence.

Do not add paid APIs, paid SDKs, or dependencies that require a paid service. Prefer Apple frameworks and on-device processing. Discuss any new third-party dependency before adding it, document why it is necessary, and prefer small, auditable packages with compatible licenses.

## Safe working practices and Git

- Inspect `git status` and relevant existing files before changing anything. Treat all pre-existing and uncommitted work as user-owned.
- Preserve existing work. Do not overwrite, discard, reset, clean, amend, rebase, force-push, or otherwise rewrite user changes unless the user explicitly requests the exact operation.
- Keep changes narrowly scoped. Do not reformat or reorganize unrelated code.
- Use Git to track work. Review `git diff` and `git status` before reporting completion. Do not commit, tag, or push unless explicitly requested.
- Standing user authorization: after each completed objective batch passes final validation, review an explicit staging list and the staged content for privacy, then create a separate descriptive commit and push to the existing confirmed ChartBridge GitHub remote/current development branch. Never invent a remote, stage private/generated/local files, force-push, or rewrite history. If no remote exists, retain the local commit and report setup needed. If remote history is not present locally, stop and report divergence. Preserve a local commit if authentication fails; report commit hash, branch, destination, push result and working-tree status.
- Never expose credentials, tokens, personal data, OCR source images, extracted private content, or model prompts in source control, logs, fixtures, screenshots, or diagnostics.
- Report what was actually run. Never claim a build, test, simulator check, accessibility check, or performance result that was not observed.
- Report every relevant warning, skipped check, flaky result, and failure honestly. Do not hide failures by weakening assertions, deleting tests, suppressing diagnostics, or silently changing requirements.

## Tooling and documentation

- Use XC-MCP for Xcode builds, test execution, scheme inspection, simulator selection, app installation and launch, screenshots, accessibility-tree inspection, and simulator interaction. Use direct `xcodebuild` or `simctl` commands only when XC-MCP is unavailable or cannot perform the required diagnostic, and disclose the fallback.
- For unfamiliar, version-sensitive, or newly introduced APIs, consult Context7 or official Apple documentation before implementation. Prefer primary Apple documentation when sources disagree. Record material availability constraints in code or tests where appropriate.
- Use terminal commands and local search for inspection and focused automation, while respecting repository instructions and preserving user changes.

## Architecture

- Keep dependencies directed and explicit. Separate app composition, feature presentation, domain logic, and infrastructure concerns such as OCR, persistence, networking, and model integration.
- Keep business rules and chart calculations in UI-independent, deterministic types that can be tested without SwiftUI, devices, network access, OCR engines, or generative models.
- Define protocols at meaningful boundaries and inject dependencies. Avoid global mutable state, hidden singletons, service locators, and view models that combine navigation, persistence, OCR, calculations, and rendering.
- Prefer small, cohesive feature modules or Swift packages when they create real ownership and test boundaries. Do not split code into modules solely for appearance.
- Model domain state explicitly, including missing, unverified, verified, invalid, loading, and failure states. Do not encode these distinctions with magic values or ambiguous optionals.
- Keep SwiftUI views declarative and focused on presentation. Move parsing, validation, OCR reconciliation, chart math, and side effects into appropriate testable components.

## Swift 6 concurrency

- Compile new code under Swift 6 strict concurrency checking and resolve concurrency diagnostics rather than suppressing them.
- Use structured concurrency. Prefer `async`/`await`, task groups, actors, and cancellation propagation over detached tasks, callbacks, semaphores, or unstructured fire-and-forget work.
- Isolate UI-observable state to `@MainActor`. Keep CPU-heavy OCR processing, image preparation, and chart calculations off the main actor, returning immutable `Sendable` values to the UI.
- Require cross-isolation values to conform to `Sendable`. Avoid `@unchecked Sendable`; if unavoidable, document the invariant and add focused tests.
- Make cancellation, task lifetime, priority, error propagation, and actor ownership explicit. Check cancellation during long-running OCR or data-processing work.
- Do not hold locks across suspension points or use blocking waits to bridge asynchronous code.

## Accessibility-first SwiftUI

- Accessibility is a release requirement, not a cleanup task. Design every screen and component for VoiceOver, Dynamic Type, Switch Control, keyboard access where applicable, sufficient contrast, Reduce Motion, and increased-contrast settings.
- Give interactive elements meaningful labels, values, hints, traits, identifiers, and logical focus order. Combine or contain accessibility elements intentionally; never rely on visual position, color, shape, or gesture alone to communicate meaning.
- Charts must have an equivalent nonvisual representation: a concise accessible summary plus navigable data points or an accessible table. Announce verification state, units, trends, selected values, and missing data without requiring interpretation of geometry or color.
- Support all Dynamic Type sizes, including accessibility categories. Prefer semantic text styles and flexible layouts; do not clip, truncate essential content, or lock important text to fixed sizes.
- Maintain touch targets of at least 44 by 44 points and avoid inaccessible custom controls when a native control can express the behavior.
- Add stable accessibility identifiers for UI tests, but do not substitute identifiers for user-facing accessibility labels.
- Validate accessibility through XC-MCP simulator accessibility-tree inspection and interaction at representative text sizes and settings. Treat critical accessibility regressions as test failures.

## Deterministic chart data and calculations

- ChartBridge calculations must be deterministic, reproducible, and independent of generative AI. Use pure functions and immutable inputs wherever practical.
- Define units, input validation, ordering, interpolation rules, date/calendar/time-zone behavior, numeric precision, rounding, and missing-data handling explicitly. Use decimal arithmetic where domain accuracy requires it; never rely on display formatting as a calculation step.
- Preserve source values separately from normalized, derived, and display values. Every displayed result must be traceable to validated inputs and a named calculation path.
- Never invent, extrapolate, or silently substitute missing values. Represent missing or invalid inputs explicitly and prevent calculations that cannot be supported.
- Add table-driven boundary tests, regression fixtures, and reference examples for chart calculations. The same validated inputs must always produce the same results across runs.
- Generative AI may explain deterministic results or suggest a review, but it must never supply authoritative numeric inputs, change formulas, override validation, or replace deterministic calculations.

## OCR verification and truthfulness

- Treat every OCR result as an untrusted candidate. Preserve provenance such as source image/page or region, raw recognized text, confidence when available, normalization steps, and verification state.
- Never present an OCR-derived value as confirmed data until it has passed explicit verification. Visually and accessibly distinguish unverified, verified, rejected, ambiguous, and missing values.
- Require user review or a documented deterministic verification rule before promoting OCR data to verified state. Low-confidence, conflicting, out-of-range, or structurally inconsistent results must require review.
- Never invent missing characters or values, silently repair ambiguous OCR, or infer a number merely because it would make a chart complete. Keep unknown data unknown.
- Allow users to inspect the source context and correct or reject extracted values. Retain an auditable distinction between the original OCR candidate and user-confirmed corrections.
- Tests must cover OCR ambiguity, partial recognition, locale-sensitive numbers, negative values, decimal separators, units, duplicates, outliers, missing rows, and failed recognition.

## Apple Foundation Models and generative features

- Treat Apple Foundation Models features as optional enhancements. Before every use, check compile-time/OS API availability and the model's runtime availability or readiness using the documented Apple API.
- Provide a complete deterministic fallback when the framework, model, compatible hardware, language, or required resources are unavailable. Core chart creation, validation, correction, and calculation must continue without generative AI.
- Do not send private content to external model services. Do not add paid model APIs. Prefer on-device processing and minimize prompts and retained data.
- Validate all structured model output against strict schemas and domain rules. Label generated explanations appropriately; never describe model output as verified fact without deterministic evidence.
- A model may not confirm OCR values, invent missing data, override user verification, alter deterministic calculations, or bypass validation and privacy rules.

## Privacy and security

- Practice data minimization: collect, retain, and process only what the user explicitly needs. Prefer on-device OCR, models, calculations, and storage.
- Request permissions only at the moment they are needed, explain their purpose, and handle denial without coercion or loss of unrelated functionality.
- Do not transmit chart images, OCR text, derived health or financial information, or other user content without explicit informed user action and a clearly disclosed destination.
- Use platform protections for sensitive local data and temporary files. Define deletion and retention behavior; remove temporary OCR artifacts promptly when no longer required.
- Redact sensitive values from logs and analytics. Do not use production user content in tests or previews.
- Validate external inputs, imported files, URLs, and model output. Apply least privilege and secure defaults.

## Testing and verification

- Use Swift Testing for deterministic unit and integration tests where it provides clear parameterization and concurrency support. Use XCTest/XCUITest for UI automation, application lifecycle behavior, performance measurements, and APIs not yet supported by Swift Testing.
- Every bug fix must include a regression test when technically feasible. New domain rules, chart calculations, OCR verification transitions, and availability fallbacks require focused tests.
- Keep tests deterministic and isolated. Do not depend on live networks, paid services, uncontrolled clocks, current locale/time zone, random ordering, or generative output. Inject clocks, calendars, locales, UUID sources, storage, OCR engines, and model clients as needed.
- Do not weaken or delete tests simply to obtain a green run. When a test cannot run, report the exact reason and what remains unverified.
- Before completion, use XC-MCP to build the relevant scheme and run the smallest relevant test set, then broader tests when warranted. Capture exact failures and diagnostics.

## Simulator validation

- Use XC-MCP to select, boot, install, launch, and validate on an appropriate iPhone simulator. Do not claim simulator validation based only on a successful compilation.
- Validate representative compact and large-screen iPhones and the oldest and newest supported iOS runtimes when those runtimes are installed.
- Exercise critical flows with VoiceOver-oriented accessibility-tree inspection, accessibility Dynamic Type sizes, light and dark appearance, increased contrast, Reduce Motion, common locales, and interrupted or unavailable OCR/model states as relevant.
- Verify both successful and failure paths, including permission denial, cancellation, empty data, invalid OCR, offline operation, and unavailable Foundation Models.
- Save screenshots or recordings only when they are useful for verification and contain no private data.

## Performance

- Protect launch time, interaction responsiveness, scrolling, chart updates, memory, and energy use. Never perform OCR, image decoding, large parsing, model inference, or expensive chart calculations synchronously on the main actor.
- Measure before optimizing. Use XCTest performance metrics, Instruments, signposts, or XC-MCP diagnostics as appropriate, and record the scenario and device/simulator context.
- Bound image resolution, memory use, concurrency, retries, and cache growth. Stream or incrementally process large inputs when practical and release temporary resources promptly.
- Make rendering work proportional to visible data. Avoid unnecessary view invalidation, repeated parsing, duplicate calculations, and unbounded collections.
- Add regression coverage or documented performance budgets for critical paths once baselines exist. Report measured regressions honestly rather than masking them with reduced test workloads.

## Completion reports

Every completion report must summarize changed files, user-visible or architectural impact, verification performed, exact test/build results, known limitations, and remaining risks. Clearly distinguish passing checks, failing checks, and checks not run. Include `git status` and do not imply that uncommitted work was committed or pushed.
