# ChartBridge — competition-readiness package

## Overview

Problem: visual charts can exclude people who cannot see or comfortably interpret their layout.

Intended users: people who benefit from readable text, explicit data review, structured exploration or speech, including blind and low-vision users. Accessibility benefits are design goals, not a certification of real-user testing.

Solution and impact: ChartBridge recognizes supported charts locally, keeps estimates visibly unverified, and enables calculations, explanations, speech and saving only after explicit human confirmation. Users can understand the confirmed data without relying on visual geometry.

Scope: simple single-series vertical/horizontal bars, marked lines in source order and labeled circular pies. JPEG/PNG or one unencrypted PDF page. No promise of general graphs, perfect OCR or numerical x-axis calibration.

Safeguards: immutable source evidence stays separate from corrections; missing data is never invented; edits revoke verification and stale insights/speech/export authorization. AI cannot confirm values, author authoritative numbers or override arithmetic. Optional Apple Foundation Models may select allowlisted findings; displayed facts/wording remain deterministic, with an availability/error fallback.

Privacy: no account, telemetry, paid API or upload. Source content stays in the preview session. Explicit local saves retain verified values, not original files, and are excluded from backup. Sharing requires a destination chosen by the user; exported copies are outside app control.

## Recommended demonstration: Library Activities

Fictional reference: Art 20, Music 60, Coding 80 attendees. Inspect actual recognition before recording; correct values openly if needed. This is guidance, never a production extraction answer key. Other samples: Volunteer Hours (Garden 20, Library 60, Shelter 80); Weekly Visitors (Week A 20, B 60, C 40, D 80); Travel Choices (Walk 20%, Bus 30%, Cycle 50%).

### Approximately 2–3 minute script

| Time | Action and narration |
|---|---|
| 0:00–0:20 | Launch; complete or skip welcome. “Charts can hide information behind a visual layout. ChartBridge offers text and speech from data you review.” Open Try a Sample Chart → Library Activities → Open Sample. |
| 0:20–0:45 | Show the fictional source/reference, tap Analyze Chart. “This is real local recognition and measurement. Results are estimates, not verified facts.” Do not hide recognition failures. |
| 0:45–1:25 | Open Review and Verify. Show one evidence disclosure, raw confidence versus measurement uncertainty, and optional crop. Correct title/units/values if necessary. Explicitly confirm each category. “Confirmation accepts my reviewed inputs, not a claim that OCR is infallible.” |
| 1:25–1:50 | Show deterministic findings. Correct reference totals are 160 attendees; Coding minus Art is 60. Show point comparison or explorer. “These calculations use only confirmed values.” Do not claim the printed example was recognized perfectly. |
| 1:50–2:15 | Choose Explain This Chart. Describe the actual displayed attribution. “Compatible Apple Intelligence can select validated findings; otherwise a complete deterministic explanation works.” Never imply AI ran when fallback is displayed. |
| 2:15–2:35 | Read explanation/current point, then stop; explore previous/next. With VoiceOver active, focus text and use VoiceOver gestures instead of competing TTS. Rehearse this on a real device first. |
| 2:35–3:00 | Save Verified Chart, prepare reports and choose PDF or text sharing. Show Save to Files only if actually exercised. “The saved record contains verified values, not my source image.” Close and reopen from Saved Charts if time permits. |

If analysis fails, explain the limitation and retry a clearer input. Never switch to fabricated candidates or claim an unexecuted live demo passed. Generation/OCR latency can vary; keep narration flexible.

## Feature and validation checklist

Observed Objective 17–18 closeout: generic Debug build passed with zero errors and one AppIntents warning; the focused Mac-hosted Swift Testing batch passed all 36 tests across seven suites. All four samples passed real Vision/geometry recognition within a 2-unit/percentage-point test tolerance, remained unverified, and passed explicit-confirmation/revocation checks. This is host automation, not a manual iPhone demonstration or general accuracy guarantee.

| Area | Implemented | Automated coverage / remaining work |
|---|---|---|
| Onboarding/Help | Skip, progress, local completion, replay, recovery/privacy text | Host state/persistence tests; first-launch presentation and focus need runtime checks |
| Samples | Four deterministic local renderers; real import/analyzer; reference disclosures | Focused host checks exercise real Vision/geometry and unverified trust boundary; see final validation record for observed outcomes |
| Verification/insights | Corrections, evidence, per-value confirmation, Decimal calculations, revocation | Existing host trust/arithmetic regressions; full updated UI/AX5 workflow remains untested in this pass |
| Explanation/speech | On-device optional AI, deterministic fallback, ordered explorer, playback | Host fallback/state checks; real model availability, VoiceOver, audio interruption and device speech need manual validation |
| Save/export | Protected local records, conflict checks, PDF/text reports, native sharing | Host storage/report checks; real share sheet, protected storage while locked and PDF/UA audit remain |

## Submission checklist

- App name/display name: ChartBridge.
- Short description: “Review supported charts on-device, explicitly verify values, and understand them through text, calculations and speech.”
- App icon: missing; original licensed artwork and asset integration still needed. No placeholder artwork or externally downloaded assets added.
- Launch: generated native launch screen; welcome shown on first use. No runtime launch review in this pass.
- Permissions: native document selection; no unnecessary camera/photo/network permission requests.
- Screenshots/recording: not captured in this pass; produce from a rehearsed, truthful synthetic demo.
- Demo video: still needed; use the script above and show actual attribution and correction.
- Repository/source: local Git baseline exists; report final commit/remote status separately. No remote should be invented or existing history overwritten.
- Accessibility: semantic text/headings/native controls, scalable layout and nonvisual data presentation implemented. Real VoiceOver, AX5, light/dark, increased contrast, keyboard and Switch Control testing still needed.
- Known warnings: unresolved SwiftUI invalid-frame runtime warning; AppIntents metadata-skipped build warning. Neither is claimed fixed.
- Official verification required: current Congressional App Challenge rules, district eligibility, deadlines, submission fields, video requirements, authorship and licensing requirements. No current competition-compliance claim is made.
- Before submission: real-device extraction accuracy/memory/latency, AI availability/fallback, source lifecycle, save/reopen/delete and PDF/text sharing validation.

## Technical architecture

Swift 6 strict-concurrency SwiftUI app, iOS 26+. Presentation uses the existing design system and MainActor observable state. Actor services perform bounded ImageIO/PDFKit importing, Vision OCR, raster extraction and optional Apple Foundation Models selection. UI-independent verification produces immutable trusted snapshots; deterministic Decimal calculations feed insights, explorer, speech and reports. Actors serialize protected versioned local storage/report work. Samples render pixels only and enter that same pipeline. UserDefaults stores only onboarding completion; no new service, dependency or parallel verification engine is introduced.
