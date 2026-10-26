# ChartBridge runtime validation — 25 October 2026

## Scope and environment

This is a partial evidence-driven validation pass, not a competition-readiness certification. The repository began clean at commit 2ba4f8b on main. There is no configured Git remote. User library contents were not deleted or used as fixtures.

Xcode 26.6 (17F113), Swift 6.3.3, macOS 26.5.1; iPhone 17 Pro simulator, iOS 26.5 (23F77). iPhone 17e and Pro Max are installed but not included in this focused runtime matrix. Only iOS 26.5 is installed. No physical iPhone is connected. AX5 command-line tooling and idb are absent: their checks are BLOCKED. AX5 Dynamic Type is a separate simulator setting, not a claim that the AX5 tool ran.

XC-MCP performed builds, simulator launch, configuration, screenshots and XCTest runs. Because idb is unavailable, native XCTest accessibility audits and hierarchy attachments were used. Terminal fallbacks read historical unified logs, exported xcresult attachments and symbolicated framework addresses with LLDB. Apple documentation and SDK audit headers informed the native audit integration.

## Changes and evidence

- **Missing bar categories:** a public photograph returned only three of five recognized categories with no completeness warning. Rectangle filtering had omitted textured bars. The extractor now rejects a recognized-category/bar-count mismatch. It does not infer missing values. A real-Vision synthetic regression removes one bar component and confirms rejection. This is fail-safe improvement, not better numerical recovery.
- **Explorer accessibility value:** literal escaped interpolation exposed code instead of the current position. Corrected to the actual item number; runtime assertion observed “Item 1 of 3.”
- **Home library shortcut:** native audit reported unsupported text scaling, then a small hit region. Semantic subheadline sizing and a 44-point minimum inside the button label corrected those specific findings in the later standard-size run.
- **Text scaling:** Help disclosure text, Skip and Import Done now have explicit semantic fonts. Onboarding progress has a 44-point presentation region.
- **Question text:** explicit primary foreground/body styling improves contrast intent, but native audit findings remain. No audit categories or findings are suppressed.
- **Test privacy:** DEBUG-only UUID-scoped temporary libraries isolate all UI-test launches from the user's real saved library. No shipping persistence behavior is redirected.
- **Failure fixtures:** DEBUG malformed PDF and oversized-file cases exercise the real importer. The corpus test is opt-in and never downloads inputs. SwiftPM excludes ignored work artifacts.

## SwiftUI frame warning

Exact captured message: **Invalid frame dimension (negative or non-finite).**

Reproduced twice during the standard/light verified-question/speech/value-edit journey at 16:36:33 and 16:36:41 local time. Unified logging backtraces resolved to SwiftUICore _FrameLayout.init and **SwiftUI.InputAccessoryBar.body.getter +172**, not a chart geometry calculation. Relevant framework UUIDs: SwiftUI 2332EF71-3E29-3E60-9849-ACDD69B6B8EF; SwiftUICore B956B64A-AF8D-3B4B-8027-702BB1F65374.

Small workaround: remove the two app keyboard-accessory toolbars and retain keyboard dismissal as ordinary accessible controls in the question input and review bottom inset. No logging is silenced and no speech/chart feature is removed. A subsequent five-minute log window contained no matching warning. Final reproduction coverage is recorded below; absence in a narrower window is not proof for every layout/configuration.

## Runtime scenario ledger

PASS applies only to the asserted scenario, not the entire UI test or a full VoiceOver evaluation.

| Scenario | Expected | Observed / status |
| --- | --- | --- |
| Initial home launch | Home becomes usable | PASS, installed and launched through XC-MCP |
| Native file picker cancel | Return to unchanged import panel | PASS, standard-size runtime |
| Preview, analyze, review synthetic bar chart | Unverified candidates, no auto-trust | PASS |
| Confirm every value | Unlock trusted insights | PASS |
| Save verified chart | Explicit saved confirmation | PASS |
| Ask highest value | Answer from current snapshot | PASS |
| Unsupported question | Honest unsupported answer | PASS |
| Ambiguous comparison | Category-selection clarification | PASS |
| Explorer next | Ordered point and meaningful position | PASS, Item 1 of 3 |
| Play / pause / resume / stop | Visible states follow actions | PASS; UI states only, audio not listened to |
| Replay then background | Stop; no automatic resume | PASS |
| Cancel precision edit | Preserve verification/value | PASS |
| Change verified value | Revoke trust and remove Ask entry | PASS |
| Reverify then reopen Ask | Fresh conversation | Initial harness FAIL: tap hit persistent Save controls, confirmed by failure hierarchy showing update/copy dialog; tighter scroll-safe tap bounds added |
| JPEG/PNG/PDF preview and unsupported/malformed/oversized retry | Correct preview or honest error, reachable retry | PASS, all six cases in AX5/dark test |
| Precision keyboard edit/save/cancel | Return to current review; no frame fault in observed log window | PASS, focused standard/light regression |
| Native standard-size accessibility audits | No findings | FAIL: latest standard pass before final text-scaling fixes found 9 Home, 7 Help, 3 onboarding, 4 import, 0 empty library, 3 Ask findings |
| Physical VoiceOver swipes, focus and audio coexistence | Real assistive interaction | NOT TESTED, no connected device |
| AX5 CLI / idb hierarchy | Run installed tool | BLOCKED, executables absent |
| Replace/background import while pending | Cancel/discard old work | NOT TESTED at runtime |
| Cancel/navigate away/new chart during OCR | No stale publication | NOT TESTED at runtime |
| Rapid speech taps / new chart / external audio interruption | No stale or overlapping playback | NOT TESTED at runtime |
| Pending AI/Ask navigation and verification edits | Cancel stale work | NOT TESTED at runtime; focused host tests cover authorization/cancellation boundaries |
| Repeated save / separate copy / invalid save | Explicit, idempotent storage | Host tests PASS; runtime NOT TESTED |
| PDF/text export, share cancel, export cleanup | Current-only reports and cleanup | Host report tests PASS; runtime NOT TESTED |
| Reduce Motion, increased contrast, hardware keyboard, Switch Control | Accessible interaction | NOT TESTED in this pass |
| Intermediate text size and other device models | Representative layout | NOT TESTED |

Final AX5/dark batch: 3 selected UI methods; 1 passed (all six import fixtures), 1 failed native accessibility audits, 1 canceled after XC-MCP's 300-second timeout. The xcodebuild process continued after the tool timed out and was interrupted to retain a readable result bundle. Duration about six minutes; this batch is NOT a clean pass. The canceled chart journey had reached the first highest-value question tap. Screenshots/hierarchies were captured; a reviewed Home AX5 screenshot showed wrapping and scrolling, not proof that every control/screen was unclipped. Result bundle: Test-ChartBridge-2026.10.25_16-42-29--0400.xcresult.

The focused iOS ExtractionTests Swift Testing suite passed all 8 methods (45 fixtures each through geometry and end-to-end Vision paths) in 91.890 seconds. XC-MCP's summary incorrectly reported 0/0; the full Swift Testing log explicitly records all eight passes. No test was inferred from the wrapper summary.

Short keyboard regression: PASS, testPrecisionEditorKeyboardRoundTrip, standard/light text on iPhone 17 Pro, 1/1 test in 85.568 seconds (XC-MCP ID 899bff10-1dcd-46d0-9918-5a1086fc575c). Both Save Changes and Cancel returned from the precision editor. Unified logs for the three-minute window covering this test contained no Invalid frame dimension warning. This validates the editor subset of the reproduction, not the complete original Ask/speech/edit journey.

## OCR evaluation

See [PublicCorpus.md](PublicCorpus.md) for independent ground truth, per-type metrics, source links, pinned hashes, tolerances and reproduction instructions. Seventeen documents were evaluated: fifteen existing synthetic controls and **two externally authored images**. One external image is a photographed fictional educational chart; the other is an actual government statistical chart. Neither is redistributed in Git.

Synthetic completion: vertical 4/4 (including PDF), horizontal 3/3, marked line 3/3, pie 2/3. Matched-value MAE respectively 0.1843 axis units, 0.0296 units, 0.1571 units and 0.0635 percentage points. These are conditional matched-value metrics, not overall real-world accuracy. Unsupported mixed/stacked and multipage inputs were rejected.

Before the completeness guard, the public bar photograph yielded 3/5 labels (MAE 19.65 units against approximate visual ground truth), a false-clean result. Afterward it is explicitly rejected; external false-clean cases fell from 1 to 0, while external completion did not improve. The government pie and one printed-percentage synthetic pie remain rejected. Broader public horizontal/line coverage and numerical-recovery improvements remain uncompleted. All returned OCR candidates stayed unverified.

## Builds, tests and observations

- Initial generic Simulator Debug build PASS.
- Final generic Simulator Debug build PASS, ID 00a22493-dc61-463e-9b0b-a5afe9c5e488. One Apple tooling warning: App Intents metadata extraction skipped because the app has no AppIntents dependency. No Swift 6 concurrency diagnostic was emitted in that build.
- Opt-in full host run: 85 Swift Testing tests in 12 suites passed, including the corpus diagnostic. A corpus diagnostic pass means trust-boundary assertions passed, not that every image extracted.
- Default host rerun also succeeded; the opt-in corpus is disabled without its environment flag.
- Three earlier standard/light runtime runs failed native accessibility audits. The third also exposed the test tap-coordinate problem described above. They are not reported as passing tests.
- Synthetic screenshots/hierarchies and native audit attachments remain in ignored DerivedData/work directories. No private chart screenshots are committed.
- Observed host import+Vision+geometry latencies were roughly 0.59–1.10 seconds per document in a diagnostic run. This is not an iPhone benchmark. No Instruments memory, energy, signpost or stall profile was collected. No crash was observed in the exercised app paths.

## Remaining priorities and Git

P1: resolve remaining native accessibility findings; perform real VoiceOver gesture/focus/speech testing; finish interrupted import/OCR/export runtime scenarios. Broader OCR corpus coverage is required before competition-level accuracy claims.

P2: repeat the full original standard-size Ask/speech/edit frame-warning journey after the keyboard workaround, plus intermediate sizing and larger-device checks. Investigate remaining public/printed pie rejections without loosening verification.

Git: main, with reviewed fixes prepared for a descriptive local commit; the resulting hash is in the final handoff. No remote exists, so pushing is blocked until the user supplies an intended destination. Never invent one.
