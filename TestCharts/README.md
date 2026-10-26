# Manual import documents

Synthetic, local-only test content for hands-on testing. These are real PNG and PDF documents, not app-embedded fixture screenshots. The generator does not import the app's fixture renderer or extraction code. Font family, dimensions, colors, labels, and layouts vary. No extraction algorithms were changed to accommodate these files.

The PNG/PDF outputs are intentionally ignored by Git, alongside all imported chart documents. Only this documentation and the synthetic generator are versioned; regenerate the named files locally when needed. Existing local copies are preserved.

Run `generate_charts.py` with Python, Pillow, and reportlab. The script uses macOS Arial and Georgia fonts. Regeneration overwrites only its 15 named generated documents; preserve any manual edits before running it.

| Document | Ground truth |
|---|---|
| 01_vertical_basic.png | Beans 20; Carrots 35; Peas 28 |
| 02_vertical_negative.png | North -20; Central 30; South 10 |
| 03_vertical_gridlines.png | Reading 15; Art 42; Music 26; Coding 34 |
| 04_horizontal_basic.png | Garden 15; Library 30; Shelter 22 |
| 05_horizontal_long_labels.png | Neighborhood cleanup 24; After-school tutoring 38; Public library workshops 17 |
| 06_horizontal_negative.png | January -20; February 30; March 10 |
| 07_line_basic.png | Week A 10; Week B 25; Week C 18; Week D 40 |
| 08_line_declining.png | Week A 45; Week B 33; Week C 24; Week D 12 |
| 09_line_gridlines.png | Week A 15; Week B 32; Week C 22; Week D 44 |
| 10_pie_basic.png | Walking 45%; Bus 30%; Cycling 25% |
| 11_pie_four_slices.png | Parks 40%; Library 27%; Roads 21%; Arts 12% |
| 12_pie_printed_percentages.png | Science 50%; Art 30%; Music 20%; percentages printed |
| 13_multipage_test.pdf | Two pages: basic vertical and horizontal charts; expected importer rejection |
| 14_chart_single_page.pdf | One page: same ground truth as basic vertical chart |
| 15_unsupported_chart.png | Stacked bars plus a second-series trend; expected unsupported/review |

## Simulator location

Files > Browse > On My iPhone > ChartBridge Test Charts.

The files were copied to the selected iPhone 17 Pro's existing local File Provider Storage, not into ChartBridge's sandbox or production resources. They persist across app relaunches and ordinary simulator restarts, but erasing the simulator removes them. The simulator container UUID/path is machine-specific and must be resolved again for another simulator.

## Manual flow

ChartBridge > Import a Chart > Choose a File > Browse > On My iPhone > ChartBridge Test Charts > choose a document. Check Ready for Analysis and the source filename, then tap Analyze Chart. Scroll to the detected type, candidates, and diagnostics. Every value remains Unverified; compare it with the table above rather than treating OCR confidence as confirmation. Use Done to return home. A two-page PDF should show a clear single-page-only error, and Choose a File remains available for retry.
