# ChartBridge

A native SwiftUI iPhone application for the Congressional App Challenge.

### Plain-English graph meaning
Explain This Chart now produces 3–5 short sentences about what the chart shows, its main comparison or observed direction, and how that view is useful. It avoids raw decimal values, totals and means in the brief explanation; detailed calculations remain available separately. Apple Intelligence selects approved qualitative takeaways grounded in the verified chart, with validated IDs and safe wording rather than unrestricted model-authored claims. When unavailable or invalid, a four-sentence built-in summary is used. No inferred causes, predictions, invented units or new numeric inputs are introduced; reports/explorer retain their detailed data separately.

## Everyday navigation and saving (post-roadmap phase 1)
The current interface uses Home, My Charts and Help tabs. Home provides Analyze Chart, Try Sample Chart and three recent charts; tapping a recent chart opens it directly in My Charts. The searchable native library is newest-first, supports pull-to-refresh, and exposes Rename/Delete through swipe actions and the context menu. Deletion always asks for confirmation.

Complete verification makes a persistent bottom Save Chart control available immediately, without waiting for insights, AI or reports. First Save writes verified values directly to the protected local library and reports Saved only after success. Repeated saves of that same snapshot are idempotent. Edits revoke verification as before; once reconfirmed, Update Chart explicitly offers updating the existing record with a current-digest check or saving a separate copy. Copies get a new identity and preserve values/provenance; a retry of the same copy request does not duplicate it. Identical content under independently created chart identities is not globally merged. Reopened saved records remain validated, read-only chart details; rename is available in the library.

Export PDF and Export Text open native file-export dialogs; Share opens native sharing with a PDF report. Reports are generated lazily when the system asks for bytes, checking live verification before generation and again at delivery. Export/share never substitute for local Save. Review fields remain directly editable; ambiguous/rejected candidates show Use Entered Value, and only explicit Confirm Value verifies them. Compact typography, reduced card padding, optional source/candidate previews and separate insight/explanation/explorer/export groups reduce clutter without changing extraction algorithms.

See Docs/PostRoadmapUI.md for validation and limitations. The feature inventory below also preserves earlier development milestones and may describe superseded labels/navigation.

## Current foundation
- One SwiftUI app entry point and a scrollable home screen.
- ChartBridge heading, accessibility mission subtitle, and native Import a Chart button.
- Native Files import supports JPEG, PNG, and single-page PDFs with an accessible preview.
- Semantic text styles, system colors, header accessibility trait, native alert, and a labeled button with an explanatory hint.
- No third-party dependencies, network access, photo-library permissions, or paid APIs. Verified charts can be explicitly saved locally.
- Step 2 adds a small shared design system, native blue primary action, semantic cards, a Saved Charts empty state, and explicitly future-facing on-device privacy copy.
- All text scales with Dynamic Type; cards grow vertically in a scroll view. Increased Contrast strengthens card outlines. No custom animation is used, including under Reduce Motion.

## Open and validate
Open ChartBridge.xcodeproj and select the shared ChartBridge scheme.
Requires Xcode 26 or newer, Swift 6, and iOS 26.0 or newer.
The app is iPhone-only; the bundle identifier is the local placeholder org.chartbridge.ChartBridge.
Device signing requires your own development team; simulator builds need no team.
Use XC-MCP to build and run the scheme on an installed iPhone simulator.
The ChartBridgeUITests target checks the home screen, native picker cancellation, imported previews, and error/retry accessibility.
Swift 6 strict concurrency checking is enabled for all targets.

## Domain and verification
Domain/BarChart.swift is UI-independent and represents an ordered single series with an immutable chart kind (vertical bar, horizontal bar, line, or pie).
It retains chart identity, axes, units, provenance, raw candidate text, decimal values, origins, and review history.
Status is derived: needsReview, partiallyVerified, or userVerified. Only explicit confirmation of a valid candidate verifies it.
Editing or rejecting a verified value revokes verification. Missing, ambiguous, and rejected values cannot enter a complete trusted snapshot.
Decimal input uses an explicit ASCII sign/integer/fraction grammar with up to 28 digits. Commas, exponents, whitespace, and inferred corrections are rejected; zero and negatives are supported.

## Import boundaries and privacy
Select one file through Files. Access to security-scoped URLs is released after reading.
Actual content is checked through ImageIO or PDFKit, independently of the extension.
Files are limited to 20 MiB; raster inputs to 40 megapixels and 20,000 pixels per side; PDF page dimensions to 14,400 points per side.
JPEG/PNG previews are orientation-aware downsampled images. PDFKit renders a single page to a bounded canvas. Previews have a maximum dimension of 1,600 pixels.
Encrypted/password-protected and multipage PDFs are rejected with instructions to choose an unencrypted, single-page copy.
Original bytes and source metadata stay in memory for the current preview session and are discarded when it closes. Explicitly saving a verified chart retains only confirmed values and minimal metadata, not the original file. Nothing is uploaded.
Ready for Analysis means only that import and preview succeeded. Analyze Chart explicitly starts on-device OCR and geometric estimation; it never verifies values.
Cancellation is cooperative between read/decode stages; an in-progress Apple decoder call cannot be interrupted.

## Tests and verification
ChartBridgeTests compiles the same domain/import source files into a UI-independent unit test target.
Swift Testing covers verification transitions, trusted snapshots, invalid inputs, content type detection, image bounds, PDF restrictions, local files, and cancellation.
UI fixtures are synthetic and gated behind DEBUG launch arguments; Release builds contain no fixture-generation path.
The real Files picker is opened and cancelled in UI tests. Preview success/failure tests pass synthetic bytes through the production decoder; external provider success and real device permission behavior still need manual validation.
Objectives 5–6 validation uses 18 Swift Testing tests (including parameterized cases and 90 fixture evaluations) and four XCUITests. See Docs/ExtractionAccuracy.md for measured results and validation scope.
XC-MCP's summary currently counts XCTest only; consult full logs for Swift Testing results.
Accessibility hierarchies and synthetic screenshots were inspected; real VoiceOver speech was not tested.

## On-device OCR and extraction
Analysis/OCR.swift uses accurate English Apple Vision text recognition without automatic language correction.
Raw strings, alternatives, confidence, normalized top-left bounding boxes, orientation, and SHA-256 image identity are retained.
JPEG/PNG orientation is normalized by the importer; PDF pages use the same bounded image pipeline.

Independent extractors analyze solid vertical bars, solid horizontal bars, connected single-series line graphs with visible markers, and complete circular pies with adjacent readable labels.
The classifier tries each evidence model and returns ambiguous if more than one is plausible. No fixture name or expected number is read by the analyzer.
Axis scales are fitted from observed ticks. Three or more ticks check linear consistency; two ticks always require review. Missing ticks are never invented.
Bar endpoints and point markers are geometric estimates. Pie percentages come from measured radial slice angles. Printed values are kept separately and cross-checked.
Grouped/stacked/3D shapes, missing markers, intersecting lines, missing category labels, incomplete pies, and indistinguishable boundaries return diagnostic rejection or review states.
The tested scope is deliberately narrow: upright, high-contrast, light-background, simple charts. See the accuracy report for limitations.

Every result remains Unverified. The existing review engine now retains chart kind and a distinct geometric-estimate origin.
Global uncertainty yields ambiguous review entries; editing or rejecting previously confirmed values still revokes verification.
No Analyze Chart action confirms data, invents missing categories, or creates a trusted snapshot.

The import preview provides processing/cancellation, detected type, accessible candidate rows, source/calibration evidence, uncertainty, and retry.
VoiceOver announcements signal analysis completion; full VoiceOver speech/navigation testing remains manual work.
Processing stays on-device, with cooperative cancellation between stages. There are no cloud/paid APIs or third-party packages.

Development references: Apple Vision VNRecognizeTextRequest documentation via Context7, plus official Apple ImageIO/PDFKit documentation.

## Editable verification and evidence (Objectives 7–8)
Analyze Chart results now open Review and Verify. Edit titles, units, category labels and values; explicitly resolve ambiguous entered numbers, confirm individual values, or reject them. Original extraction evidence remains separate. Editing invalidates confirmation, including invalid or empty numerical drafts. A trusted snapshot is available only through the existing domain engine after complete explicit confirmation and validation.
The review parser accepts the locale decimal separator and decimal digits, without grouping, exponent notation, silent repair or rounding. The original canonical parser is unchanged. Pie values must be 0–100 and total 100 within 0.5 percentage points; totals are never normalized. Points remain in source order; numerical x calibration is not added.
Review evidence separates raw text confidence, raster uncertainty, calibration, diagnostics and human verification. Support labels follow documented deterministic rules, not an invented overall accuracy percentage. Full technical details are optional disclosures. Review state is in-memory for the current import preview only.
Pie units are fixed to percent. Empty/duplicate labels, invalid or missing numbers, and out-of-range percentages receive inline errors and correction counts. A pie-total mismatch blocks a complete trusted snapshot without guessing which slice is wrong. Title/unit edits revoke all confirmations; duplicate-label edits also revoke affected confirmations. Accepted estimates retain their decimal representation rather than being rounded to six fractional places.

Evidence agreement is deterministic: printed versus geometric values agree within the larger of raster uncertainty or 2% of axis span (bars/lines), or 2 percentage points (pies). Strong support additionally requires consistent calibration, no extra warnings, and valid text confidence of at least 0.8 for every associated observation. These are descriptive support rules, not accuracy probabilities or verification. Original evidence is never replaced by a user correction.

An optional source-region image uses a bounded, off-main ImageIO crop of the normalized preview. Accessible text remains sufficient without the image. No new permission, upload, analytics, cloud service, or dependency was added. Review edits survive back navigation within the current import preview, but closing that preview discards them.

See Docs/VerificationReview.md for the current closeout results and remaining validation limitations. The older Docs/NextSessionHandoff.md is a historical checkpoint, not the current feature inventory.

## Verified insights and on-device explanations (Objectives 9–10)
Chart Insights appears only for a complete trusted snapshot. Checked Decimal arithmetic provides totals/means, extrema/ties, stable rankings and selected comparisons; ordered line changes/trends describe observations only; pie comparisons use percentage points and never infer physical totals. Relative changes require a positive baseline. Overflow/underflow are unavailable, and rounded arithmetic is labeled approximate. Unspecified units remain explicit. Any edit/rejection removes old insights and explanation tasks; reconfirming creates a new revision.

Explain This Chart is an explicit, optional action. Apple Foundation Models availability is checked before each request. A structured on-device response may select/order only allowlisted deterministic facts; no generated prose or model-authored numbers are displayed. Invalid/empty selections, unavailable Apple Intelligence, oversized input or generation failures use the deterministic explanation. Cancellation is distinct from success. Source paths, hashes, OCR candidates and image pixels never enter the model input. No upload, paid API or dependency is used.

Host-only focused tests reuse production domain/calculation/explanation code through Package.swift: `swift test --filter ChartInsightsTests`. They need no simulator or live model. The iOS unit target also registers these tests. Runtime Foundation Models generation and this new UI still require later device/accessibility validation; compilation alone does not prove model readiness. The pre-existing SwiftUI layout warning is outside this step.

## Planned, not implemented
Physical-device accuracy/performance profiling, final app icon artwork, competition recording and the post-roadmap full-app review remain planned.

## Getting started and demonstration (Objectives 17–18)
First launch presents three brief, skippable onboarding steps. Continue/Get Started or Skip persists a completion flag locally; Help and Privacy can reopen the guide without resetting it. The DEBUG-only --skip-onboarding launch argument preserves existing UI regression setup; it does not affect Release behavior.

Try a Sample Chart opens four fictional offline charts, rendered with CoreGraphics/CoreText in production builds. Selecting a sample decodes its pixels through ChartImporter and opens the existing preview/Analyze/Review flow. Expected values appear only as transparent reference guidance and renderer/test inputs; no OCR observations, extracted values, confirmations or AI responses are injected. Samples remain subject to recognition errors, metadata correction and explicit per-value verification. Saving, speech, exploration and sharing reuse the existing verified-snapshot controls.

Help describes scope, privacy, accessibility, retry/correction, unavailable Apple Intelligence and storage/export recovery. Analysis, incomplete verification and report sections add contextual guidance. Samples and onboarding use native scrolling layouts, semantic headings and Dynamic Type; runtime accessibility validation is still needed.

Docs/CompetitionReadiness.md contains the product overview, 2–3 minute demo script, technical architecture, feature status and submission checklist. It does not assert current competition eligibility or deadlines. The display name is explicitly ChartBridge; no app icon asset exists yet. No external artwork, screenshots or video were generated.
See AGENTS.md for mandatory correctness, privacy, accessibility, and verification rules.
App artwork and App Store signing/distribution configuration remain future work.

## Speech and accessible exploration (Objectives 11–12)
Complete verification enables ordered text exploration, previous/next, extrema jumps (first tied item in source order), summary return and current/all-chart reading. Observed line changes never infer intervals; pie differences use percentage points. The existing calculations are prepared once per snapshot for insights and exploration.

One on-device AVSpeechSynthesizer controller per review provides explicit play, pause, resume, stop, replay and completion/interruption state. It stops on backgrounding, audio interruptions/route changes, leaving review, or verification changes; stale replay content is revoked immediately. No audio is saved or uploaded. When VoiceOver is active, read actions focus accessible text instead of starting competing synthesized speech; VoiceOver uses its own reading gestures. Enabling VoiceOver stops existing synthesized playback. Controls, labels and announcements were reviewed in code only; actual speech timing, VoiceOver focus, audio interruptions and AX5 layout require later device validation.

Focused host checks: `swift test --filter ChartAccessibilityTests`. No simulator is required.

## Local library, reports and test expansion (Objectives 13–14)
Save verified values from Chart Insights; View Saved Charts reopens validated records, renames with explicit confirmation of retaining values, and deletes only after confirmation. Version-1 Codable records use per-file atomic writes, size bounds, corruption checksums, duplicate/conflict checks, and domain-engine replay of persisted explicit confirmations. Invalid/incompatible files are retained and reported, never silently migrated or promoted to trusted data. Creation/modification dates, provenance origin and snapshot revision are preserved. Original files, OCR strings, images and cached AI output are not stored.

The sandbox Application Support library is excluded from backup and uses complete file protection on iOS. Checksums detect accidental corruption, not malicious same-sandbox tampering; there is no supported JSON import. There is no cloud sync. Saving briefly disables review editing; subsequent verification changes revoke report authorization, insights and speech.

Prepare Reports creates a plain-text report and a paginated CoreText/CoreGraphics PDF with selectable text, logical text tags, verified values, findings, explanation, date and verification note. Native ShareLink supports PDF sharing/Save to Files and plain-text sharing only on user action. Representation closures recheck live authorization before supplying bytes. No temporary export files are written. Full PDF/UA compliance and share-sheet/VoiceOver behavior have not been certified.

Focused host batch: `swift test --filter 'Chart(Library|Report|Insights|Accessibility)Tests'`. Tests use unique temporary directories, controlled clocks, failed-write injection and host PDF text extraction. Existing device-only import/extraction and UI fixtures remain preserved and require later authorized execution.

## Reliability and interface polish (Objectives 15–16)
Imports still use actual ImageIO/PDFKit content validation, balanced security-scoped access, bounded 20 MiB reads, image dimension limits and downsampled previews. PDF origins must also be finite; only local file URLs are accepted. Each import has a lightweight session identity instead of using image bytes as a SwiftUI identity. Debug UI fixtures decode in memory and no longer create temporary source files.

Raster masking and component traversal now check cancellation even across background/already-visited pixels. Extraction thresholds, geometry and deterministic calculations are unchanged. Cancellation is cooperative: synchronous ImageIO, PDFKit and Vision calls cannot be interrupted mid-call. Explanation/report actors retain at most one calculated findings entry and reuse it only when the complete trusted snapshot matches, including values and metadata. No telemetry, performance framework or dependency was added; performance gains have not been device-profiled.

Library operations check cancellation before work and immediately before file mutation; replay cancellation stays cancellation, not corruption. The flat UUID-owned library still rejects symbolic links and invalid records, uses atomic protected writes, and never accepts a decoded verification status. Local UI mutations are serialized, rename/delete alerts retain their selected record, and cancelled refresh/open operations do not publish error announcements. An atomic mutation that already completed is not rolled back by later cancellation. Export preparation is invalidated when the explanation changes; live verification authorization remains required for share delivery.

The existing native interface now explains the import-to-verification workflow and the subsequent insights/listen/save options, provides labeled verification progress and completion guidance, emphasizes individual confirmation, and collapses extraction notes without hiding actionable validation errors. Insights distinguish deterministic findings, exploration, optional explanation, speech and sharing. Saved-chart actions include local processing feedback and contextual deletion confirmation. Semantic colors, Dynamic Type, native controls, scrolling and minimum touch targets remain in use; no onboarding, animation or speculative screen was added.

Host checks now also exercise the production importer: `swift test --filter 'Chart(ImportSafety|Reliability|Library|Report|Insights|Accessibility)Tests'`. This pass deliberately uses a generic Debug simulator-SDK build and Mac-hosted tests only—not simulator runtime/UI, screenshots or accessibility scans. The earlier “Invalid frame dimension (negative or non-finite)” warning remains unresolved: source inspection found only positive minimum sizes, finite fixed maximum widths and flexible infinite maximum widths, not a clear invalid fixed-frame calculation. Navigation/keyboard-toolbar layout around multiline review fields is a plausible area to inspect later, not a proven cause. AX5, appearance, real VoiceOver/speech, share-sheet behavior and physical-device performance still need authorized runtime validation.

## Interactive Visual Insights and numeric presentation
Verified charts now open a Swift Charts overview with native selection plus a labeled picker and a complete expandable text alternative. Tap Highest & Lowest, Compare Two Points or Ranking for focused detail screens. Line charts instead feature Observed Trend, preserving source order and showing start/end/net change; ranking is not suggested as their primary interpretation. Native back navigation returns to the verified chart, with saving and short explanations unchanged.

Bar scales include zero, including negative and all-zero data. Equal full-precision values share competition ranks (1, 1, 3). Comparisons name the first selected value as baseline, report absolute differences and permit relative change only for a positive baseline. Pie differences are percentage points, never relative percentage change or inferred physical totals. Pies use sectors only for a complete, exactly 100-percent distribution; otherwise shares use zero-based horizontal bars without normalization.

Drawing is limited to the first 30 values in the displayed order, with an explicit notice for larger datasets; every value remains available in the picker and text alternative. Plot geometry uses Double drawing precision, while decisions/calculations retain Decimal precision. Visual destinations observe live verification authorization and stop showing stale data. Saved-chart authorization survives pushing a detail screen but is revoked when its record changes or is removed.

ChartNumberFormat is presentation-only: locale-aware numbers with at most two fractional digits, two digits for noninteger displayed values, no ordinary scientific notation, and explicit approximation when precision is reduced. Nonzero magnitudes below displayed precision are described as between zero and 0.01 rather than falsely declared zero. Editable fields, raw OCR/source evidence, canonical model facts and persisted records keep original precision. Read-only review, calculations, explanation facts, explorer/speech and reports share the formatting. Confirmation still does not establish physical measurement accuracy.

New focused host tests cover formatting/locales, full-precision ties, negative/zero scales, comparison baseline policy, pie shares, source order and stale verification. This batch uses a generic simulator-SDK build and Mac-host tests only. No simulator runtime, UI tests, screenshots, AX5 layout or real VoiceOver validation is claimed.

## Natural listening and precision-safe verification editing

Verification rows show locale-aware, two-decimal presentation values. Edit Value opens a native sheet containing the exact original input, not the rounded display. Draft changes stay local until Save Changes; Cancel and dismissal do not touch confirmation, inputs or provenance. Saving an actual valid edit revokes confirmation. Unchanged, invalid or stale drafts cannot silently overwrite the chart. Original extraction estimates, uncertainty and evidence remain unchanged.

Listen to your chart presents one deterministic 2–4 sentence paragraph, a primary Play/Pause/Resume control, optional Replay/Stop, and separate Previous/Next point exploration. With VoiceOver, read actions focus text instead of starting competing speech. More details retains technical descriptions, verification/accuracy context, extrema jumps and the full calculation text. Summaries and selected-value speech do not prepend chart type, attribution, navigation, state or accuracy boilerplate; explanation attribution remains visible in the interface.

The short offline narration uses the current trusted snapshot and the same Decimal calculation engine: bars describe extrema and a useful gap, lines describe source-order endpoints and observed changes, and pies describe shares and percentage-point gaps. Missing units are omitted rather than invented. Ties, single values, negative/zero values and approximate estimates have explicit wording. Speech uses whole numbers only at magnitudes of at least ten when the display error is at most one percent, with “about” when rounded; otherwise it uses at most two decimals. Pie shares retain two-decimal precision. Stored data and calculation inputs never use these rounded strings.

Focused tests cover the editing contract, localized/invalid/stale drafts, speech wording for every chart type, absence of technical boilerplate, estimate preservation and speech revocation/replacement after edits. Existing UI regression source now opens/saves/cancels the editor, but UI tests are not run in this batch. Real VoiceOver timing and AX5 layout remain unvalidated.

## Second interface refinement

Home keeps one Import Chart action, a quiet sample action and direct recent-chart reopening. Sample charts now push into the import workflow inside their existing navigation stack instead of opening another sheet/navigation stack. The three tabs remain Home, My Charts and Help, and tab changes preserve the current saved-chart path.

Import shows a bounded preview by default with file details collapsed. Analysis has one primary next action, while re-analysis is secondary and requires confirmation once a review exists. Cancelling the file picker preserves the open preview; picker failures are reported without discarding it. Recognition algorithms, input limits and on-device processing are unchanged.

Verification has concise progress, expandable chart metadata/evidence and a single prominent action naming the next valid candidate. It confirms only that one value after an explicit tap. Ambiguous, rejected, missing, duplicate-label and invalid candidates are not suggested; they retain their existing correction/resolution flow. Individual row confirmation stays available. Full-precision value editing and original uncertainty/provenance remain intact.

Save Chart remains independent of explanations/exports. The footer distinguishes Not saved yet, Changes not saved and Saved, with explicit update/copy confirmation, deduplicated writes, visible failures and View in My Charts after saving. Redundant Back to My Charts actions were removed in favor of native back navigation. At accessibility Dynamic Type sizes, verification/save actions move into scrolling content rather than taking most of the screen as a fixed footer. Fixed icon widths became flexible minimums. This is a preventive layout improvement, not a claimed fix for the earlier untraced runtime frame warning.

Insights use clearer navigation rows with chevrons and structured calculation labels/values, without rebuilding their existing Swift Charts. Average replaces Arithmetic mean in presentation; unknown units are omitted from casual value labels and explained in details. Short deterministic listening is preserved with a clearer selected-point position. Optional explanation generation is secondary, and technical notes stay expandable. Share PDF, Export PDF and Export Text are grouped in a native report menu, separate from saving.

The library keeps search, newest-first ordering, native rename/delete confirmation and source-preserving failure handling. Saved details add an explicit open retry. Shared headings, semantic surfaces, status labels, notices and empty states keep light/dark and increased-contrast behavior consistent without adding a theme framework, dependency or custom animation. Help is organized by task with expandable answers.

Focused tests add single-value confirmation suggestions, explicit ambiguity resolution and tab-path preservation; existing saving, speech, trust and formatting tests remain. UI regression source follows the new metadata disclosures and precision editor, but is not executed in this pass. No simulator runtime, screenshots, GUI interaction, AX5 visual check or real VoiceOver validation is claimed.

## Ask Your Chart

Open a completely verified chart's Insights and choose **Ask Your Chart**. The native question field, suggested questions and explicit category/baseline pickers answer supported English questions without changing the redesigned navigation. Answers are deterministic and on-device; this feature does not use a language model, network or additional dependencies.

Supported questions include highest/lowest (including ties), bar-category sums and arithmetic averages, bar/pie rankings, named comparisons, explicit positive-baseline percentage changes, line endpoints/overall change/observed trends/largest consecutive changes, pie segment shares and a simple explanation. Examples: “Which category is highest?”, “Compare Art and Reading”, “Percentage change from Art to Reading”, “Which point changed the most?”, and “What percentage does Art represent?”. Unknown/ambiguous category names require a picker; unsupported questions do not generate guessed answers. Comparisons match full normalized labels, not substrings. Causes, predictions, arbitrary multi-part questions and inferred physical pie totals are unsupported. Pie comparisons use percentage points, never relative percentage change or rescaled shares. Line totals/averages and rankings are intentionally not offered. Bar sums/means describe only shown category values, not an inferred population statistic.

Only a complete trusted snapshot can construct numerical answers. Full snapshot equality, not just identity/revision, gates history and speech. Changed or revoked verification hides and clears answers, cancels structured view tasks, stops playback and rejects late results. Up to 12 exchanges remain in memory for the active chart; they are not persisted or included in saved reports. Ask Your Chart is bounded to 256 values, with ranking/consecutive-change output limited to 20 rows and a notice directing larger results to the explorer. All calculations reuse checked Decimal operations; readable answers use at most two fractional digits and retain approximation/very-small-value wording. Stored and editable values keep full precision.

Listen reads a short answer through the existing local speech service, with Stop Reading while active. When VoiceOver is active it focuses the answer instead of starting competing audio. Native headings, menu/picker controls, semantic typography and flexible scrolling preserve existing accessibility conventions. This batch validates with a generic simulator-SDK build and focused Mac-hosted Swift Testing, not simulator launch, screenshots, UI tests, AX5 visual inspection or real VoiceOver speech testing.

## Stability and reliability pass

Derived insights, explanations, speech and report delivery now check the complete trusted snapshot, including independent copies that share an ID and revision. Revoked authorization clears displayed derived content and pending explanation work. Comparison-unit handling is consistent when missing-unit markers contain whitespace. Single-page PDF importing preserves page rotation and nonzero page origins within the existing decode bounds. New library records cannot exceed the same 2,000-record limit used by listing, while existing idempotent saves and updates retain their original behavior. Text-only export skips PDF rendering rather than generating unused pages. The UI design, recognition scope, explicit confirmation rules and local-only privacy remain unchanged. See Docs/StabilityAudit.md for the checklist, reproduced failures, regression coverage and remaining runtime checks.

## Version control and local artifacts
Completed objective batches are committed after validation and privacy review, then pushed only to an existing, confirmed ChartBridge GitHub remote/current branch. Without a remote, keep the local commit and request setup; never invent a destination or overwrite remote history. See AGENTS.md for the standing workflow.

Generated manual PNG/PDF documents, imports, local user documents, build/test outputs, signing credentials and machine-specific tool state are ignored. Synthetic test renderers and the TestCharts generator are tracked. Historical NextSessionHandoff.md and VerificationReview.md reports remain local because they contain workstation paths and session details; references above to those reports describe local development history, not portable tracked documentation. The tracked ExtractionAccuracy.md records earlier synthetic-fixture measurements, not fresh certification of current UI/device behavior.
