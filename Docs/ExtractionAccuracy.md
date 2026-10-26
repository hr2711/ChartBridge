# ChartBridge Objectives 5–6 validation report
Date: 2026-10-24. Environment: Xcode 26.6, Swift 6.3.3, iPhone 17 Pro simulator, iOS 26.5, Debug.
Final unit run: 22a289a3-adfb-4964-ac52-8c9b885a6bc5. Full log confirms 18 Swift Testing tests passed in four suites.
XC-MCP's compact summary misreports Swift Testing failures as success/zero tests; this report uses full assertion logs.

## Evaluation rules fixed before measurement
- Bar/line values: absolute error at most 2 axis units.
- Pie values: absolute error at most 2 percentage points.
- Categories: exact recognized string match to ground truth. No spelling correction against expected names.
- Each accepted fixture must have the expected type, category count, and all values within tolerance.
- Intentionally unsupported/ambiguous fixtures must not produce a clean candidate result. They may return explicitly needs-review evidence.
- "Clean" means no additional diagnostic conflicts; it NEVER means verified or trusted.
- Ground-truth values and fixture names are used only by the renderer/test evaluator, never by the production analyzer.
- Numeric errors are measured only on output values with matched ground-truth categories. Rejected fixtures are counted separately and are not assigned a zero error.
- Aggregate MAE is weighted by the number of matched categories, using the per-fixture log rounded to four decimals.
- These are synthetic fixtures, not evidence of accuracy on arbitrary real-world charts.

## Aggregate results
Classified is the number returning the correct chart kind; it includes explicit needs-review outputs. Rejected includes unsupported/ambiguous outputs.
The denominator includes intentionally unsupported structures. Correct category/value totals are over returned, matched rows.
The four end-to-end corpora contain 17 vertical, 10 horizontal, 9 line, and 9 pie fixtures (45 total). Each is also run with ideal text evidence.
The OCR-error vertical fixture returns needs-review estimates from remaining ticks; it does not receive a clean result.

| Stage | Type | Fixtures | Classified | Correct categories | Correct values | MAE (units or pp) | Rejected | Needs review | False clean |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Geometry | Vertical bar chart | 17 | 11 | 33 | 33 | 0.1090 | 6 | 2 | 0 |
| Geometry | Horizontal bar chart | 10 | 7 | 21 | 21 | 0.0560 | 3 | 1 | 0 |
| Geometry | Line graph | 9 | 5 | 20 | 20 | 0.0534 | 4 | 0 | 0 |
| Geometry | Pie chart | 9 | 4 | 13 | 13 | 0.0855 | 5 | 1 | 0 |
| E2E | Vertical bar chart | 17 | 11 | 33 | 33 | 0.3985 | 6 | 9 | 0 |
| E2E | Horizontal bar chart | 10 | 7 | 21 | 21 | 0.2028 | 3 | 6 | 0 |
| E2E | Line graph | 9 | 5 | 20 | 20 | 0.6762 | 4 | 5 | 0 |
| E2E | Pie chart | 9 | 4 | 13 | 13 | 0.0855 | 5 | 1 | 0 |

## End-to-end Vision OCR + raster analysis — fixture-by-fixture

| Fixture | Result/type | Categories | Values within tolerance | MAE | Review state | Elapsed seconds |
|---|---|---:|---:|---:|---|---:|
| Vertical bar chart / basic | Vertical bar chart | 3/3 | 3/3 | 0.3243 | Needs review | 0.946 |
| Vertical bar chart / colors | Vertical bar chart | 3/3 | 3/3 | 0.5330 | Needs review | 0.963 |
| Vertical bar chart / unequal | Vertical bar chart | 3/3 | 3/3 | 0.1136 | Needs review | 0.953 |
| Vertical bar chart / grid | Vertical bar chart | 3/3 | 3/3 | 0.3243 | Needs review | 0.949 |
| Vertical bar chart / decimal | Vertical bar chart | 3/3 | 3/3 | 0.3122 | Needs review | 0.958 |
| Vertical bar chart / negative | Vertical bar chart | 3/3 | 3/3 | 0.6153 | Unverified candidates | 0.940 |
| Vertical bar chart / nonzero | Vertical bar chart | 3/3 | 3/3 | 0.2376 | Unverified candidates | 0.945 |
| Vertical bar chart / printed | Vertical bar chart | 3/3 | 3/3 | 0.5330 | Needs review | 0.966 |
| Vertical bar chart / monochrome | Vertical bar chart | 3/3 | 3/3 | 0.5330 | Needs review | 0.961 |
| Vertical bar chart / conflict | Vertical bar chart | 3/3 | 3/3 | 0.5330 | Needs review | 0.964 |
| Vertical bar chart / missingTicks | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.956 |
| Vertical bar chart / grouped | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.994 |
| Vertical bar chart / stacked | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.963 |
| Vertical bar chart / 3D | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.967 |
| Vertical bar chart / ocrError | Vertical bar chart | 3/3 | 3/3 | 0.3243 | Needs review | 0.970 |
| Vertical bar chart / rotated | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.955 |
| Vertical bar chart / lowResolution | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.125 |
| Horizontal bar chart / basic | Horizontal bar chart | 3/3 | 3/3 | 0.1225 | Needs review | 1.089 |
| Horizontal bar chart / longLabels | Horizontal bar chart | 3/3 | 3/3 | 0.1225 | Needs review | 1.086 |
| Horizontal bar chart / colors | Horizontal bar chart | 3/3 | 3/3 | 0.1225 | Needs review | 1.092 |
| Horizontal bar chart / negative | Horizontal bar chart | 3/3 | 3/3 | 0.2203 | Unverified candidates | 0.954 |
| Horizontal bar chart / grid | Horizontal bar chart | 3/3 | 3/3 | 0.2713 | Needs review | 1.090 |
| Horizontal bar chart / printed | Horizontal bar chart | 3/3 | 3/3 | 0.2802 | Needs review | 1.093 |
| Horizontal bar chart / conflict | Horizontal bar chart | 3/3 | 3/3 | 0.2802 | Needs review | 1.092 |
| Horizontal bar chart / missingTicks | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 1.081 |
| Horizontal bar chart / grouped | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 1.036 |
| Horizontal bar chart / stacked | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 1.101 |
| Line graph / basic | Line graph | 4/4 | 4/4 | 0.6787 | Needs review | 0.981 |
| Line graph / decreasing | Line graph | 4/4 | 4/4 | 0.6787 | Needs review | 0.979 |
| Line graph / decimal | Line graph | 4/4 | 4/4 | 0.6633 | Needs review | 0.993 |
| Line graph / grid | Line graph | 4/4 | 4/4 | 0.6818 | Needs review | 0.987 |
| Line graph / printed | Line graph | 4/4 | 4/4 | 0.6787 | Needs review | 0.993 |
| Line graph / missingMarker | Chart not supported reliably | 0/4 | 0/4 | n/a | Rejected | 0.987 |
| Line graph / intersecting | Chart not supported reliably | 0/4 | 0/4 | n/a | Rejected | 0.995 |
| Line graph / missingTicks | Chart not supported reliably | 0/4 | 0/4 | n/a | Rejected | 0.981 |
| Line graph / log | Chart not supported reliably | 0/4 | 0/4 | n/a | Rejected | 0.985 |
| Pie chart / basic | Pie chart | 3/3 | 3/3 | 0.0926 | Unverified candidates | 1.011 |
| Pie chart / four | Pie chart | 4/4 | 4/4 | 0.0694 | Unverified candidates | 1.017 |
| Pie chart / printed | Pie chart | 3/3 | 3/3 | 0.0926 | Unverified candidates | 1.013 |
| Pie chart / similar | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 1.003 |
| Pie chart / missingLabels | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 1.003 |
| Pie chart / donut | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 1.005 |
| Pie chart / exploded | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 1.007 |
| Pie chart / 3D | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 1.000 |
| Pie chart / conflict | Pie chart | 3/3 | 3/3 | 0.0926 | Needs review | 1.008 |

## Geometry-only analysis with known OCR observations — fixture-by-fixture

| Fixture | Result/type | Categories | Values within tolerance | MAE | Review state | Elapsed seconds |
|---|---|---:|---:|---:|---|---:|
| Vertical bar chart / basic | Vertical bar chart | 3/3 | 3/3 | 0.1136 | Unverified candidates | 0.394 |
| Vertical bar chart / colors | Vertical bar chart | 3/3 | 3/3 | 0.1136 | Unverified candidates | 0.389 |
| Vertical bar chart / unequal | Vertical bar chart | 3/3 | 3/3 | 0.1136 | Unverified candidates | 0.399 |
| Vertical bar chart / grid | Vertical bar chart | 3/3 | 3/3 | 0.1136 | Unverified candidates | 0.392 |
| Vertical bar chart / decimal | Vertical bar chart | 3/3 | 3/3 | 0.1098 | Unverified candidates | 0.397 |
| Vertical bar chart / negative | Vertical bar chart | 3/3 | 3/3 | 0.1231 | Unverified candidates | 0.374 |
| Vertical bar chart / nonzero | Vertical bar chart | 3/3 | 3/3 | 0.0568 | Unverified candidates | 0.378 |
| Vertical bar chart / printed | Vertical bar chart | 3/3 | 3/3 | 0.1136 | Unverified candidates | 0.376 |
| Vertical bar chart / monochrome | Vertical bar chart | 3/3 | 3/3 | 0.1136 | Unverified candidates | 0.374 |
| Vertical bar chart / conflict | Vertical bar chart | 3/3 | 3/3 | 0.1136 | Needs review | 0.369 |
| Vertical bar chart / missingTicks | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.366 |
| Vertical bar chart / grouped | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.409 |
| Vertical bar chart / stacked | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.375 |
| Vertical bar chart / 3D | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.380 |
| Vertical bar chart / ocrError | Vertical bar chart | 3/3 | 3/3 | 0.1136 | Needs review | 0.367 |
| Vertical bar chart / rotated | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.368 |
| Vertical bar chart / lowResolution | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.000 |
| Horizontal bar chart / basic | Horizontal bar chart | 3/3 | 3/3 | 0.0490 | Unverified candidates | 0.505 |
| Horizontal bar chart / longLabels | Horizontal bar chart | 3/3 | 3/3 | 0.0490 | Unverified candidates | 0.506 |
| Horizontal bar chart / colors | Horizontal bar chart | 3/3 | 3/3 | 0.0490 | Unverified candidates | 0.514 |
| Horizontal bar chart / negative | Horizontal bar chart | 3/3 | 3/3 | 0.0980 | Unverified candidates | 0.371 |
| Horizontal bar chart / grid | Horizontal bar chart | 3/3 | 3/3 | 0.0490 | Unverified candidates | 0.506 |
| Horizontal bar chart / printed | Horizontal bar chart | 3/3 | 3/3 | 0.0490 | Unverified candidates | 0.502 |
| Horizontal bar chart / conflict | Horizontal bar chart | 3/3 | 3/3 | 0.0490 | Needs review | 0.502 |
| Horizontal bar chart / missingTicks | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.503 |
| Horizontal bar chart / grouped | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.462 |
| Horizontal bar chart / stacked | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.514 |
| Line graph / basic | Line graph | 4/4 | 4/4 | 0.0568 | Unverified candidates | 0.398 |
| Line graph / decreasing | Line graph | 4/4 | 4/4 | 0.0568 | Unverified candidates | 0.397 |
| Line graph / decimal | Line graph | 4/4 | 4/4 | 0.0398 | Unverified candidates | 0.396 |
| Line graph / grid | Line graph | 4/4 | 4/4 | 0.0568 | Unverified candidates | 0.399 |
| Line graph / printed | Line graph | 4/4 | 4/4 | 0.0568 | Unverified candidates | 0.396 |
| Line graph / missingMarker | Chart not supported reliably | 0/4 | 0/4 | n/a | Rejected | 0.397 |
| Line graph / intersecting | Chart not supported reliably | 0/4 | 0/4 | n/a | Rejected | 0.402 |
| Line graph / missingTicks | Chart not supported reliably | 0/4 | 0/4 | n/a | Rejected | 0.394 |
| Line graph / log | Chart not supported reliably | 0/4 | 0/4 | n/a | Rejected | 0.395 |
| Pie chart / basic | Pie chart | 3/3 | 3/3 | 0.0926 | Unverified candidates | 0.431 |
| Pie chart / four | Pie chart | 4/4 | 4/4 | 0.0694 | Unverified candidates | 0.433 |
| Pie chart / printed | Pie chart | 3/3 | 3/3 | 0.0926 | Unverified candidates | 0.432 |
| Pie chart / similar | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.441 |
| Pie chart / missingLabels | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.429 |
| Pie chart / donut | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.414 |
| Pie chart / exploded | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.424 |
| Pie chart / 3D | Chart not supported reliably | 0/3 | 0/3 | n/a | Rejected | 0.417 |
| Pie chart / conflict | Pie chart | 3/3 | 3/3 | 0.0926 | Needs review | 0.439 |

## End-to-end diagnostic evidence

- Vertical bar chart / basic: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Vertical bar chart / colors: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Vertical bar chart / unequal: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Vertical bar chart / grid: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Vertical bar chart / decimal: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Vertical bar chart / negative: All results are unverified. Geometry-derived values are estimates.

- Vertical bar chart / nonzero: All results are unverified. Geometry-derived values are estimates.

- Vertical bar chart / printed: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Vertical bar chart / monochrome: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Vertical bar chart / conflict: All results are unverified. Geometry-derived values are estimates.; Printed value disagrees with bar geometry for Alpha.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Vertical bar chart / missingTicks: Vertical bar chart: Missing, conflicting, or nonlinear axis ticks.; Horizontal bar chart: Missing, conflicting, or nonlinear axis ticks.; Line graph: A single connected line series with discrete point markers is required.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Vertical bar chart / grouped: Vertical bar chart: Category association is missing or ambiguous; grouped/stacked bars are unsupported.; Horizontal bar chart: Missing, conflicting, or nonlinear axis ticks.; Line graph: A single connected line series with discrete point markers is required.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Vertical bar chart / stacked: Vertical bar chart: Bars do not share a baseline; stacked, grouped, or 3D layout may be present.; Horizontal bar chart: Missing, conflicting, or nonlinear axis ticks.; Line graph: A single connected line series with discrete point markers is required.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Vertical bar chart / 3D: Vertical bar chart: Additional adjacent shapes suggest stacked bars, shadows, or 3D decoration.; Horizontal bar chart: Additional adjacent shapes suggest stacked bars, shadows, or 3D decoration.; Line graph: A single connected line series with discrete point markers is required.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Vertical bar chart / ocrError: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Vertical bar chart / rotated: Vertical bar chart: Missing, conflicting, or nonlinear axis ticks.; Horizontal bar chart: Missing, conflicting, or nonlinear axis ticks.; Line graph: A single connected line series with discrete point markers is required.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Vertical bar chart / lowResolution: Input is too small or not upright after normalization. Provide a clear upright image.

- Horizontal bar chart / basic: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Horizontal bar chart / longLabels: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Horizontal bar chart / colors: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Horizontal bar chart / negative: All results are unverified. Geometry-derived values are estimates.

- Horizontal bar chart / grid: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Horizontal bar chart / printed: All results are unverified. Geometry-derived values are estimates.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Horizontal bar chart / conflict: All results are unverified. Geometry-derived values are estimates.; Printed value disagrees with bar geometry for Alpha.; Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Horizontal bar chart / missingTicks: Vertical bar chart: Missing, conflicting, or nonlinear axis ticks.; Horizontal bar chart: Missing, conflicting, or nonlinear axis ticks.; Line graph: At least three visible point markers are required; no points are inferred from the curve.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Horizontal bar chart / grouped: Vertical bar chart: Missing, conflicting, or nonlinear axis ticks.; Horizontal bar chart: Category association is missing or ambiguous; grouped/stacked bars are unsupported.; Line graph: A single connected line series with discrete point markers is required.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Horizontal bar chart / stacked: Vertical bar chart: Missing, conflicting, or nonlinear axis ticks.; Horizontal bar chart: Bars do not share a baseline; stacked, grouped, or 3D layout may be present.; Line graph: At least three visible point markers are required; no points are inferred from the curve.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Line graph / basic: All results are unverified. Geometry-derived values are estimates.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Line graph / decreasing: All results are unverified. Geometry-derived values are estimates.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Line graph / decimal: All results are unverified. Geometry-derived values are estimates.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Line graph / grid: All results are unverified. Geometry-derived values are estimates.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Line graph / printed: All results are unverified. Geometry-derived values are estimates.; Only two ticks were recognized. Linearity is unconfirmed; the estimates require review.

- Line graph / missingMarker: Vertical bar chart: No reliable set of solid bars was found.; Horizontal bar chart: No reliable set of solid bars was found.; Line graph: Category and marker counts disagree; missing markers or labels require review.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Line graph / intersecting: Vertical bar chart: No reliable set of solid bars was found.; Horizontal bar chart: No reliable set of solid bars was found.; Line graph: Multiple strokes intersect a data column; multi-series graphs are unsupported.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Line graph / missingTicks: Vertical bar chart: No reliable set of solid bars was found.; Horizontal bar chart: No reliable set of solid bars was found.; Line graph: Missing, conflicting, or nonlinear axis ticks.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Line graph / log: Vertical bar chart: No reliable set of solid bars was found.; Horizontal bar chart: No reliable set of solid bars was found.; Line graph: Missing, conflicting, or nonlinear axis ticks.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Pie chart / basic: All results are unverified. Geometry-derived values are estimates.

- Pie chart / four: All results are unverified. Geometry-derived values are estimates.

- Pie chart / printed: All results are unverified. Geometry-derived values are estimates.

- Pie chart / similar: Vertical bar chart: No reliable set of solid bars was found.; Horizontal bar chart: No reliable set of solid bars was found.; Line graph: A single connected line series with discrete point markers is required.; Pie chart: Slice boundaries are missing or ambiguous.

- Pie chart / missingLabels: Vertical bar chart: No reliable set of solid bars was found.; Horizontal bar chart: No reliable set of solid bars was found.; Line graph: A single connected line series with discrete point markers is required.; Pie chart: Every pie slice needs one reliable nearby category label; no category names are invented.

- Pie chart / donut: Vertical bar chart: No reliable set of solid bars was found.; Horizontal bar chart: No reliable set of solid bars was found.; Line graph: A single connected line series with discrete point markers is required.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Pie chart / exploded: Vertical bar chart: No reliable set of solid bars was found.; Horizontal bar chart: No reliable set of solid bars was found.; Line graph: A single connected line series with discrete point markers is required.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Pie chart / 3D: Vertical bar chart: No reliable set of solid bars was found.; Horizontal bar chart: No reliable set of solid bars was found.; Line graph: A single connected line series with discrete point markers is required.; Pie chart: No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.

- Pie chart / conflict: All results are unverified. Geometry-derived values are estimates.; Printed percentage conflicts with measured angle.; Printed percentages do not sum to 100.

## Additional checks
- Accurate English Vision OCR, raw strings/confidence/source/bounds, negative grouped decimal text, percentage text, and physically rotated input with explicit orientation: passed.
- JPEG and PDF import → rendered/normalized image → actual Vision → vertical negative-value extraction: passed, all three categories and values within the original 2-unit tolerance. These are supplemental format tests, not extra rows in the 45-fixture table.
- Trusted-snapshot prevention and chart-kind preservation: asserted for every returned fixture result.
- All existing domain and import validation tests passed.
- Four XCUITests passed at light/standard and dark/AX5. After final production changes, the two affected analysis/import tests passed again in both configurations. A stronger analysis test then required an on-screen, hittable candidate for each of all four chart types; it passed at dark/AX5 (20:12:51 result bundle) and light/standard (XC-MCP da0f2732-8336-499c-964c-e36539acbfbf). AX5 screenshots confirm wrapping candidate values and Unverified text without essential truncation.
- XC-MCP accessibility inspection via idb is unavailable because idb is not installed. XCTest accessibility queries and the native Simulator accessibility tree were used instead; no real VoiceOver speech testing is claimed.
- Builds have no Swift 6 concurrency errors or warnings. Xcode emits an AppIntents metadata-skipped warning (no AppIntents dependency) and UI-test logs emit LLDB version-snapshot diagnostics; tests still completed successfully. Malformed-image tests intentionally produce ImageIO decoder diagnostics.
- Screenshots are synthetic test attachments. No private chart content is recorded.

## Performance and memory observations
End-to-end fixture execution (fixture prepared before clock start): mean 0.981 seconds, range 0.125–1.101 seconds.
This measures Debug simulator execution including import normalization, OCR, geometry, and actor hops, not physical-device performance.
Production OCR is off the main actor on an actor-isolated engine. Raster analysis runs off the main actor on ChartAnalyzer.
Existing import limits remain 20 MiB / 40 MP, with previews capped at 1600 pixels per side; OCR checks those preview dimensions before image creation.
Geometry is capped at 800 pixels per side (at most 2.56 MB RGBA), with bounded masks/visited arrays and component stacks.
Apple Vision/PDFKit working memory and peak RSS have not been profiled on a physical device. No claim of a measured peak-memory ceiling is made.
Cancellation is checked between processing stages and within component/marker loops; an in-progress Vision or decoder call cannot be interrupted.

## Supported scope and remaining limitations
- Genuine implementations exist for both bar orientations, connected single-series marked lines, and complete circular labeled pies.
- OCR often omits isolated zero ticks. No zero is synthesized. Two-tick linear estimates are needs-review; values beyond the recognized tick span are explicitly flagged as unconfirmed scale extension. Three inconsistent ticks reject a nonlinear/logarithmic scale.
- Detected grouped/stacked/3D bars, intersecting/multi-series lines, missing markers, incomplete/exploded/donut/3D pies, unreadable labels/ticks, and inadequate resolution return diagnostics.
- Clean candidates are still unverified. The review adapter marks global calibration conflicts ambiguous; no analysis operation confirms a value or creates a trusted snapshot.
- White/light-background charts, solid discernible fills, upright text, simple linear axes, clear markers, and adjacent pie labels are the tested scope.
- Detection thresholds are conservative and do not prove rejection of every 3D or multi-series design. Dark-background, textured, photographic, smooth markerless, and legend-only pie layouts are not validated.
- Numeric x-axis labels can be associated to visible line markers, but dates, logarithmic x scales, error bars, and general multi-series structures are not supported.
- Pie boundaries rely on distinguishable adjacent colors; similar colors and tiny slices may be rejected. Printed values and raster estimates remain separate.
- General legend interpretation, robust rotated-axis-title attribution, and complete text-role classification remain limited; all OCR text stays available as raw evidence.
- No editable verification interface, speech feature, Foundation Models, SwiftData, or application report-export feature was added.
- Real VoiceOver speech, Switch Control, physical-device behavior, and successful external Files-provider selection remain untested.
