# Post-roadmap phase 1 — navigation and saving

## Before and after

Before: a long home screen opened a modal saved library; nested cards mixed analysis, explanation, speech and save/export controls. Save was below the insights/report section, and repeated save attempts requested replacement even without changes.

After: Home / My Charts / Help tabs. Home has Analyze Chart, Try Sample Chart and direct recent-chart reopening. My Charts uses a searchable native newest-first list with rename/delete swipe actions and context menu, destructive confirmation, empty/error states and pull-to-refresh. Help is an independent tab rather than another home modal.

Verification immediately enables a persistent bottom Save Chart control. A successful write shows Saved and View in My Charts; reopening never depends on original files or PDF generation. On saved detail, the action returns to My Charts. Changed/reconfirmed review data uses Update Chart → explicit Update Existing Chart or Save a Separate Copy. No silent overwrite. The repository atomically checks current record digests, coalesces identical saves and preserves the original when copying or a write fails.

Export PDF, Export Text and Share are separate native controls. Transferable report delivery checks current authorization before preparing data and again before supplying bytes; no temporary export files or cloud APIs are introduced. The Apple SwiftUI Transferable fileExporter signature was checked through Context7's official Apple documentation: https://developer.apple.com/documentation/swiftui/view-presentation .

## Focused validation

New host tests cover concurrent/repeated saves, update conflicts, separate-copy identity/retry/reopening, failed writes, explicit verification and cross-tab navigation state. Existing trust/storage/report/speech/extraction tests remain available. Final observed build/test results are recorded in the completion handoff.

Observed validation: the consolidated generic Debug build passed with zero errors, one AppIntents metadata-skipped warning and no Swift 6 concurrency diagnostics. The focused Mac-hosted Swift Testing batch passed all 41 tests in eight suites, including all four real sample OCR/extraction cases. The deliberately malformed PDF emitted its expected CoreGraphics diagnostic while passing. Final lifecycle review added authorization/replay revocation when a reopened detail disappears; only the affected generic build was repeated after that correction. Host services/tests were unchanged.

UI test expectations were aligned with the new home text, direct field editing, conditional resolution actions and candidate disclosure. They were not run in this phase. No simulator boot/interaction, Xcode GUI operation, screenshots or visual/VoiceOver validation was authorized.

## Known limitations

The existing SwiftUI invalid-frame warning has no established source cause; static inspection still found no obvious negative/non-finite fixed-frame expression. It is not claimed fixed. Real-device AX5/light/dark/contrast/VoiceOver focus, native exporter/share behavior, swipe/context-menu actions, sticky save controls and modal-to-tab transitions need runtime validation. App icon artwork is still missing.

Saved chart data remains read-only after reopening except for explicitly confirmed rename; the update flow applies to edits/reconfirmation within a retained review session. Identical data from independently imported chart identities is not automatically deduplicated. Saves retain verified values only, not the source file. No original extraction math, OCR rules or verification boundaries were relaxed.
