# Local OCR evaluation corpus

This is an opt-in developer evaluation, not a shipping resource or a network test.
Run from the repository: `CHARTBRIDGE_EVALUATE_CORPUS=1 swift test --filter ChartCorpusEvaluationTests`.
The test never downloads files, corrects labels from ground truth, or confirms
recognized values. Default test runs skip this corpus when the environment flag
is absent. Missing documented files fail an explicitly enabled run.

## Inputs and provenance

The existing 15 TestCharts documents are **synthetic controls**, independently
rendered by TestCharts/generate_charts.py. Their ground truth is in
TestCharts/README.md, not inferred from ChartBridge output. Do not call these
real-world statistical examples. Twelve PNGs cover three examples of each chart
kind; a single-page PDF repeats the first bar chart, a two-page PDF should be
rejected by the importer, and a mixed/stacked figure should not yield a clean
single-series candidate. Do not overwrite any user's edited copies to regenerate
these documents.

Two externally authored images were downloaded only into ignored
`work/PublicChartCorpus/` for this evaluation. No private user file was used;
neither downloaded image is redistributed in Git.

| File | Source / use basis | Independent reference |
| --- | --- | --- |
| commons-bar.jpg | [Brigban, Bar chart.jpg, Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Bar_chart.jpg), CC0/public-domain dedication shown on the source page. A photographed educational chart, **not real census data**. | Manual readings before OCR: Park City about 4,000; Hillside about 3,500; Elmdale about 2,500; River Valley about 4,500; Cedar Grove about 2,000. These are approximate visual estimates from the axis, not exact source observations. Use 100 units as a completeness/error-screening tolerance. |
| canada-ghg-2024.png | [Environment and Climate Change Canada, 2026 executive summary, Figure ES-6](https://www.canada.ca/en/environment-climate-change/services/climate-change/greenhouse-gas-emissions/sources-sinks-executive-summary-2026.html). Public government report; local research/evaluation only, no image redistribution or endorsement claim. | Published rounded table shares: Oil and Gas 30%; Transport 22%; Buildings 12%; Heavy Industry 11%; Agriculture 10%; Electricity 7.2%; Waste and Others 6.9%. Do not normalize their rounded sum. Real statistical publication; gradients, leaders and tightly grouped labels stress the narrow supported scope. |

Downloaded bytes are pinned by SHA-256:

- commons-bar.jpg: `093142fb5ddd779763e91c1aa654acaabc5a5a4a9b87dbc8d3c07a4944b0189e`
- canada-ghg-2024.png: `355782a6755bbc401a7ab2011666ae447f733f26546494f1314c72bb4889c98a`

Source image URLs (download manually, then check hashes before evaluation):

- https://upload.wikimedia.org/wikipedia/commons/1/18/Bar_chart.jpg
- https://www.canada.ca/content/canadasite/en/environment-climate-change/services/climate-change/greenhouse-gas-emissions/sources-sinks-executive-summary-2026/_jcr_content/par/mwsadaptiveimage_1921969355/image.img.png/1776191158062.png

## Measurement rules fixed before analysis

- Exact, case-sensitive recognized label matching. No fuzzy correction or
  reference-fed OCR. Report matched labels over all expected labels, so rejected
  or missing values do not disappear from the denominator.
- Absolute errors and mean absolute relative errors use **matched returned
  values only**. Relative errors exclude zero references and use absolute
  reference magnitude for negative values. Rejections receive no fictitious zero
  error. Pie absolute errors are percentage points, not underlying physical units.
- Synthetic screening tolerance: 2 axis units / 2 percentage points, unchanged
  from earlier tests. Public photo tolerance: 100 units because its ground truth
  is a visual estimate, not a precise published data table.
- “False clean” means a clean-candidate result with wrong type, missing labels or
  errors outside the above tolerance. Clean still never means verified. Separately
  count errors outside the reported **raster** uncertainty; that uncertainty is
  not an OCR/calibration guarantee or a confidence probability.
- Timings cover host import + Vision + geometry, including actor hops, in Debug.
  They are observations under the current machine load, not device benchmarks.

## Observed results

Baseline public photo: returned three of five labels (Hillside, Elmdale, Cedar
Grove), while reporting no additional completeness diagnostic. Three matched
values had MAE 19.65 units and mean relative error about 0.71%, but those small
errors concealed the missing categories. The two omitted textured bars failed
the rectangle filter. The bar-label completeness guard now rejects the incomplete
interpretation explicitly instead of inferring values. False-clean results in
these two external images decrease from 1 to 0; **external completion is not
improved**, and no numerical-recovery improvement is claimed.

The government pie is rejected before category extraction; it does not establish
successful real-world pie support. The printed-percentage synthetic pie is also
rejected. A trial text-hole change exposed another label-association rejection
without improving completion, so it was discarded rather than loosening pie
acceptance. No pie algorithm change is included in the validated fixes.

| Synthetic controls only | Completed / fixtures | Matched / expected labels | Matched-value MAE | Mean absolute relative error |
| --- | --- | --- | --- | --- |
| Vertical bars (including PDF) | 4 / 4 | 13 / 13 | 0.1843 axis units | 0.91% |
| Horizontal bars | 3 / 3 | 9 / 9 | 0.0296 axis units | 0.13% |
| Marked lines | 3 / 3 | 12 / 12 | 0.1571 axis units | 0.80% |
| Pies | 2 / 3 | 7 / 10 | 0.0635 percentage points | 0.27% |

The mixed/stacked control is rejected by extraction; the multipage PDF is rejected
by import. No returned control is trusted automatically, and matched control
errors fall within their raster uncertainty in this run. Do not combine these
numbers into one general accuracy percentage: the inputs, units, scope and
rejection rates differ. Real-world horizontal and marked-line coverage, broader
photographic variation and published exact-value benchmarks remain missing.
