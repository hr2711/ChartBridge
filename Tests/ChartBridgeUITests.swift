import XCTest

/// Uses only synthetic chart data and a DEBUG-only, UUID-scoped temporary library.
/// Hierarchy/audit checks are not claims of VoiceOver gesture or speech testing.
final class RuntimeValidationTests: XCTestCase {
    @MainActor private func audit(_ app: XCUIApplication) throws {
        // Collect all native findings in one pass instead of stopping at the
        // first. Findings still fail the test; none are filtered or suppressed.
        let prior = continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = prior }
        var findings = 0
        try app.performAccessibilityAudit(for: .all) { issue in
            findings += 1
            print("AUDIT FINDING|\(issue.auditType.rawValue)|\(issue.element?.label ?? "Unknown element")|\(issue.detailedDescription)")
            return false
        }
        print("AUDIT COMPLETED|\(findings) findings")
    }
    @MainActor private func launch(fixture: String? = nil) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--skip-onboarding", "--ui-test-library=" + UUID().uuidString]
        if let fixture { app.launchArguments.append("--import-fixture=" + fixture) }
        app.launch()
        XCTAssertTrue(app.buttons["importChart"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<35 {
            let frame = element.frame
            // Review's persistent save controls occupy the bottom safe-area
            // inset. XCTest can call a covered scrolled element hittable.
            if element.isHittable, frame.minY > 110, frame.maxY < app.frame.maxY - 200 { return }
            let above = element.exists && frame.midY < app.frame.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.6))
            start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: above ? 180 : -180)))
        }
        XCTAssertTrue(element.isHittable, "Control must be reachable by scrolling: " + element.identifier)
    }

    @MainActor private func record(_ app: XCUIApplication, _ screen: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "Hierarchy - " + screen; tree.lifetime = .keepAlways; add(tree)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Synthetic runtime - " + screen; shot.lifetime = .keepAlways; add(shot)
        print("RUNTIME SCREEN|" + screen)
    }

    @MainActor func testHomeHelpAndImportAccessibilityAudit() throws {
        let app = launch()
        record(app, "Home")
        try audit(app)
        print("RUNTIME CHECK|Home accessibility audit completed")
        app.tabBars.buttons["Help"].tap()
        XCTAssertTrue(app.buttons["Getting Started"].waitForExistence(timeout: 5))
        record(app, "Help")
        try audit(app)
        print("RUNTIME CHECK|Help accessibility audit completed")
        app.buttons["Getting Started"].tap()
        XCTAssertTrue(app.buttons["Skip"].waitForExistence(timeout: 5))
        record(app, "Onboarding")
        try audit(app)
        app.buttons["Skip"].tap()
        app.tabBars.buttons["Home"].tap()
        let open = app.buttons["importChart"]; reveal(open, in: app); open.tap()
        XCTAssertTrue(app.buttons["chooseFile"].waitForExistence(timeout: 5))
        record(app, "Import empty")
        try audit(app)
        let choose = app.buttons["chooseFile"]; reveal(choose, in: app); choose.tap()
        let cancel = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); cancel.tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        print("RUNTIME PASS|File picker cancellation returns to import")
        app.buttons["Done"].tap()
        app.tabBars.buttons["My Charts"].tap()
        record(app, "My Charts empty")
        try audit(app)
    }

    @MainActor func testVerifiedJourneyQuestionsSpeechAndStorage() throws {
        let app = launch(fixture: "vertical")
        let open = app.buttons["importChart"]; reveal(open, in: app); open.tap()
        XCTAssertTrue(app.staticTexts["importReady"].waitForExistence(timeout: 10))
        record(app, "Chart preview")
        let analyze = app.buttons["analyzeChart"]; reveal(analyze, in: app); analyze.tap()
        XCTAssertTrue(app.staticTexts["analysisResult"].waitForExistence(timeout: 30))
        record(app, "Extraction result")
        let review = app.buttons["reviewAndVerify"]; reveal(review, in: app); review.tap()
        XCTAssertTrue(app.staticTexts["verificationProgress"].waitForExistence(timeout: 5))
        record(app, "Unverified review")
        for index in 0..<3 {
            let resolve = app.buttons["resolveValue-\(index)"]
            if resolve.exists { reveal(resolve, in: app); resolve.tap() }
            let confirm = app.buttons["confirmValue-\(index)"]; reveal(confirm, in: app); confirm.tap()
            XCTAssertEqual(app.staticTexts["reviewStatus-\(index)"].label, "Confirmed by you")
        }
        XCTAssertTrue(app.staticTexts["trustedAvailability"].label.hasPrefix("Chart verified"))
        let save = app.buttons["saveVerifiedChart"]; reveal(save, in: app); save.tap()
        XCTAssertTrue(app.otherElements["chartSaved"].waitForExistence(timeout: 3) || app.staticTexts["chartSaved"].exists)
        print("RUNTIME PASS|Verify and save")
        let ask = app.buttons["openAskYourChart"]; reveal(ask, in: app); ask.tap()
        XCTAssertTrue(app.buttons["Which category is highest?"].waitForExistence(timeout: 5))
        app.buttons["Which category is highest?"].tap()
        let answer = app.descendants(matching: .any).matching(identifier: "chartQuestionAnswer").firstMatch
        XCTAssertTrue(answer.waitForExistence(timeout: 5))
        XCTAssertTrue(answer.label.contains("highest"))
        record(app, "Ask Your Chart answer")
        try audit(app)
        print("RUNTIME PASS|Ask verified question")
        let input = app.textFields["chartQuestionInput"].exists ? app.textFields["chartQuestionInput"] : app.textViews["chartQuestionInput"]
        reveal(input, in: app); input.tap(); input.typeText("Why did this happen?")
        let submit = app.buttons["askChartQuestion"]; reveal(submit, in: app); submit.tap()
        let unsupported = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "I can't answer that from this chart yet")).firstMatch
        XCTAssertTrue(unsupported.waitForExistence(timeout: 5))
        let suggestions = app.buttons["Suggested Questions"]; reveal(suggestions, in: app); suggestions.tap()
        app.buttons["Compare two categories"].tap()
        XCTAssertTrue(app.buttons["Compare Values"].waitForExistence(timeout: 5))
        print("RUNTIME PASS|Unsupported and ambiguous questions require honest recovery")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let next = app.buttons["Next Data Point"]; reveal(next, in: app); next.tap()
        let point = app.staticTexts["explorerCurrentPoint"]
        XCTAssertTrue(point.waitForExistence(timeout: 5))
        XCTAssertEqual(point.value as? String, "Item 1 of 3")
        record(app, "Listen and Explore")
        let play = app.buttons["playChartSummary"]; reveal(play, in: app); play.tap()
        XCTAssertEqual(play.label, "Pause")
        play.tap(); XCTAssertEqual(play.label, "Resume")
        play.tap(); XCTAssertEqual(play.label, "Pause")
        let stop = app.buttons["Stop"]; reveal(stop, in: app); stop.tap()
        XCTAssertEqual(play.label, "Play Summary")
        print("RUNTIME PASS|Speech Play Pause Resume Stop state")
        let replay = app.buttons["Replay Summary"]; reveal(replay, in: app); replay.tap()
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertEqual(play.label, "Play Summary")
        print("RUNTIME PASS|Backgrounding stops speech without auto-resume")
        let edit = app.buttons["editValue-0"]; reveal(edit, in: app); edit.tap()
        XCTAssertTrue(app.buttons["saveValueEdit"].waitForExistence(timeout: 5))
        record(app, "Precision editor")
        app.buttons["Cancel"].tap()
        XCTAssertEqual(app.staticTexts["reviewStatus-0"].label, "Confirmed by you")
        reveal(edit, in: app); edit.tap()
        let field = app.textFields["reviewValue-0"].exists ? app.textFields["reviewValue-0"] : app.textViews["reviewValue-0"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
        let original = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: original.count) + "-5")
        app.buttons["saveValueEdit"].tap()
        XCTAssertEqual(app.staticTexts["reviewStatus-0"].label, "Unverified")
        XCTAssertFalse(app.buttons["openAskYourChart"].exists)
        print("RUNTIME PASS|Editing verified data revokes insights and old questions")
        let confirm = app.buttons["confirmValue-0"]; reveal(confirm, in: app); confirm.tap()
        reveal(ask, in: app); ask.tap()
        XCTAssertTrue(app.buttons["Which category is highest?"].waitForExistence(timeout: 5))
        XCTAssertFalse(answer.exists, "Old conversation must not survive changed verification")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(save, in: app); save.tap()
        XCTAssertTrue(app.buttons["Update Existing Chart"].waitForExistence(timeout: 5))
        app.buttons["Update Existing Chart"].tap()
        let viewSaved = app.buttons["viewSavedChart"]; reveal(viewSaved, in: app); viewSaved.tap()
        XCTAssertTrue(app.navigationBars["Chart"].waitForExistence(timeout: 10))
        record(app, "Reopened saved chart")
        XCTAssertTrue(app.staticTexts["Verified chart"].exists)
        print("RUNTIME PASS|Explicit update and direct reopening")
        let rankings = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Ranking")).firstMatch
        reveal(rankings, in: app); rankings.tap()
        XCTAssertTrue(app.navigationBars["Ranking"].waitForExistence(timeout: 5))
        record(app, "Ranking")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let extremes = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Highest & Lowest")).firstMatch
        reveal(extremes, in: app); extremes.tap()
        XCTAssertTrue(app.navigationBars["Highest & Lowest"].waitForExistence(timeout: 5))
        record(app, "Highest and lowest")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["My Charts"].waitForExistence(timeout: 5))
        let cell = app.cells.firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5)); cell.swipeLeft()
        app.buttons["Rename"].tap()
        let title = app.alerts.textFields.firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap()
        let oldTitle = title.value as? String ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: oldTitle.count) + "Runtime renamed chart")
        app.alerts.buttons["Rename"].tap()
        let renamedRow = app.cells.containing(NSPredicate(format: "label CONTAINS %@", "Runtime renamed chart")).firstMatch
        XCTAssertTrue(renamedRow.waitForExistence(timeout: 5))
        renamedRow.swipeLeft(); app.buttons["Delete"].tap(); app.alerts.buttons["Cancel"].tap()
        XCTAssertTrue(renamedRow.exists)
        renamedRow.swipeLeft(); app.buttons["Delete"].tap(); app.alerts.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["A home for your charts"].waitForExistence(timeout: 5))
        print("RUNTIME PASS|Rename, cancel deletion and confirmed deletion")
    }

    /// A short, independently runnable reproduction of the keyboard accessory
    /// warning. Check unified logs as well; XCTest cannot assert OSLog faults.
    @MainActor func testPrecisionEditorKeyboardRoundTrip() throws {
        let app = launch(fixture: "vertical")
        let open = app.buttons["importChart"]; reveal(open, in: app); open.tap()
        XCTAssertTrue(app.staticTexts["importReady"].waitForExistence(timeout: 10))
        let analyze = app.buttons["analyzeChart"]; reveal(analyze, in: app); analyze.tap()
        XCTAssertTrue(app.staticTexts["analysisResult"].waitForExistence(timeout: 30))
        let review = app.buttons["reviewAndVerify"]; reveal(review, in: app); review.tap()
        let edit = app.buttons["editValue-0"]; reveal(edit, in: app); edit.tap()
        let field = app.textFields["reviewValue-0"].exists ? app.textFields["reviewValue-0"] : app.textViews["reviewValue-0"]
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText("1")
        app.buttons["saveValueEdit"].tap()
        XCTAssertEqual(app.staticTexts["reviewStatus-0"].label, "Unverified")
        reveal(edit, in: app); edit.tap()
        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5)); app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["verificationProgress"].exists)
        record(app, "Precision keyboard round trip")
    }
}

// Temporary real-document smoke probe; removed after this setup session.
final class ManualDocumentSmokeTests: XCTestCase {
    @MainActor
    func testRealDocumentSmoke() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--skip-onboarding", "--ui-test-library=" + UUID().uuidString]; app.launch()
        let button = app.buttons["importChart"]
        for _ in 0..<8 { if button.isHittable { break }; app.swipeUp() }
        button.tap()
        let choose = app.buttons["chooseFile"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        for _ in 0..<8 { if choose.isHittable { break }; app.swipeUp() }
        let names = ["01_vertical_basic", "02_vertical_negative", "03_vertical_gridlines", "04_horizontal_basic", "05_horizontal_long_labels", "06_horizontal_negative", "07_line_basic", "08_line_declining", "09_line_gridlines", "10_pie_basic", "11_pie_four_slices", "12_pie_printed_percentages", "13_multipage_test", "14_chart_single_page", "15_unsupported_chart"]
        func openPicker() {
            for _ in 0..<15 { if choose.isHittable { break }; app.swipeUp() }
            choose.tap()
            let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "ChartBridge Test Charts")).firstMatch
            if !folder.waitForExistence(timeout: 3), choose.isHittable { choose.tap() }
            XCTAssertTrue(folder.waitForExistence(timeout: 8))
        }
        func cell(_ name: String) -> XCUIElement {
            app.cells.matching(NSPredicate(format: "label BEGINSWITH %@", name + ",")).firstMatch
        }
        func reveal(_ element: XCUIElement) {
            for _ in 0..<15 {
                if element.isHittable { return }
                if element.exists, element.frame.midY < app.frame.midY { app.swipeDown() }
                else { app.swipeUp() }
            }
        }
        openPicker()
        for name in names {
            let file = cell(name); reveal(file)
            XCTAssertTrue(file.isHittable, name + " must be visible in Files")
            print("FILES VERIFIED|" + file.label)
        }
        var shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Real Files picker all 15 verified"; shot.lifetime = .keepAlways; add(shot)
        // The native sheet exposes Cancel as Other on this iOS build.
        let cancel = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch
        XCTAssertTrue(cancel.exists)
        cancel.tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        print("SMOKE|cancel|returned to import panel")
        for name in ["01_vertical_basic", "04_horizontal_basic", "07_line_basic", "10_pie_basic", "14_chart_single_page", "13_multipage_test", "15_unsupported_chart"] {
            openPicker()
            let file = cell(name); reveal(file); XCTAssertTrue(file.isHittable); file.tap()
            if name == "13_multipage_test" {
                let error = app.staticTexts["importError"]
                XCTAssertTrue(error.waitForExistence(timeout: 10))
                XCTAssertTrue(error.label.contains("single-page"))
                print("SMOKE|" + name + "|" + error.label)
            } else {
                XCTAssertTrue(app.staticTexts["importReady"].waitForExistence(timeout: 10))
                let analyze = app.buttons["analyzeChart"]; reveal(analyze); analyze.tap()
                let result = app.staticTexts["analysisResult"]
                XCTAssertTrue(result.waitForExistence(timeout: 30))
                let preview = app.buttons["Preview unverified estimates"]; reveal(preview); preview.tap()
                let rows = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@", "candidate-"))
                let labels = rows.allElementsBoundByIndex.map(\.label)
                XCTAssertTrue(labels.allSatisfy { $0.contains("Unverified") })
                print("SMOKE|" + name + "|" + result.label + "|" + labels.joined(separator: " || "))
                if name != "15_unsupported_chart" {
                    XCTAssertGreaterThan(rows.count, 0, name + " must return candidates in this smoke test")
                } else {
                    XCTAssertTrue(result.label.contains("not supported") || result.label.contains("Needs review") || result.label.contains("Ambiguous"))
                }
                reveal(result)
            }
            shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Real file smoke - " + name; shot.lifetime = .keepAlways; add(shot)
            app.buttons["Done"].tap()
            XCTAssertTrue(app.buttons["importChart"].waitForExistence(timeout: 5))
            print("SMOKE|home|" + name)
            if name != "15_unsupported_chart" { app.buttons["importChart"].tap() }
        }
    }
}

final class ChartBridgeUITests: XCTestCase {
    @MainActor
    func testVerticalReviewEditingAndConfirmation() throws {
        try reviewWorkflow(kinds: ["vertical"])
    }
    @MainActor
    func testHorizontalReviewEditingAndConfirmation() throws {
        try reviewWorkflow(kinds: ["horizontal"])
    }
    @MainActor
    func testLineReviewEditingAndConfirmation() throws {
        try reviewWorkflow(kinds: ["line"])
    }
    @MainActor
    func testPieReviewEditingAndConfirmation() throws {
        try reviewWorkflow(kinds: ["pie"])
    }
    @MainActor
    private func reviewWorkflow(kinds: [String]) throws {
        continueAfterFailure = false
        for kind in kinds {
            let app = XCUIApplication()
            app.launchArguments = ["--import-fixture=" + kind]
            app.launchArguments += ["--skip-onboarding", "--ui-test-library=" + UUID().uuidString]; app.launch()
            func reveal(_ element: XCUIElement) {
                for _ in 0..<40 {
                    let frame = element.frame
                    let safeHeight = app.frame.height - 190
                    let fullyVisible = frame.height > safeHeight || (frame.minY >= 140 && frame.maxY <= app.frame.maxY - 50)
                    if element.isHittable && fullyVisible { return }
                    // A full-screen swipe can oscillate over a large AX5
                    // control. Bounded drags move toward its center without
                    // changing the requirement that the control be reachable.
                    let targetAbove = frame.midY.isFinite && frame.midY < app.frame.midY
                    let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.6))
                    let distance = targetAbove ? 180.0 : -180.0
                    start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)))
                }
                XCTAssertTrue(element.isHittable, "The requested review control must be reachable by vertical scrolling")
            }
            func valueField(_ index: Int) -> XCUIElement {
                let identifier = "reviewValue-\(index)"
                return app.textFields[identifier].exists ? app.textFields[identifier] : app.textViews[identifier]
            }
            let importButton = app.buttons["importChart"]; reveal(importButton); importButton.tap()
            XCTAssertTrue(app.staticTexts["importReady"].waitForExistence(timeout: 10))
            let analyze = app.buttons["analyzeChart"]; reveal(analyze); analyze.tap()
            XCTAssertTrue(app.staticTexts["analysisResult"].waitForExistence(timeout: 30))
            let review = app.buttons["reviewAndVerify"]; reveal(review); review.tap()
            let details = app.buttons["editChartDetails"]; reveal(details); details.tap()
            XCTAssertTrue(app.textFields["reviewTitle"].waitForExistence(timeout: 5) || app.textViews["reviewTitle"].exists)
            XCTAssertTrue(app.staticTexts["verificationProgress"].label.contains("0 confirmed"))
            let resolve = app.buttons["resolveValue-0"]; if resolve.exists { reveal(resolve); resolve.tap() }
            let confirm = app.buttons["confirmValue-0"]; reveal(confirm); confirm.tap()
            let confirmed = NSPredicate(format: "label == %@", "Confirmed by you")
            let confirmation = XCTNSPredicateExpectation(predicate: confirmed, object: app.staticTexts["reviewStatus-0"])
            let confirmedResult = XCTWaiter.wait(for: [confirmation], timeout: 5)
            if confirmedResult != .completed { print("REVIEW CONFIRM FAILURE:\n" + app.debugDescription) }
            XCTAssertEqual(confirmedResult, .completed)
            let displayed = app.staticTexts["reviewDisplayedValue-0"]
            let displayedBefore = displayed.label
            let editValue = app.buttons["editValue-0"]; reveal(editValue); editValue.tap()
            XCTAssertTrue(valueField(0).waitForExistence(timeout: 5))
            let originalPrecision = valueField(0).value as? String
            XCTAssertNotNil(originalPrecision)
            app.buttons["Cancel"].tap()
            XCTAssertEqual(displayed.label, displayedBefore)
            XCTAssertEqual(app.staticTexts["reviewStatus-0"].label, "Confirmed by you", "Opening and cancelling the value editor must not revoke verification")
            reveal(editValue); editValue.tap()
            let value = valueField(0)
            XCTAssertTrue(value.waitForExistence(timeout: 5))
            XCTAssertEqual(value.value as? String, originalPrecision)
            reveal(value); value.tap()
            let old = value.value as? String ?? ""
            value.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + "12")
            app.buttons["saveValueEdit"].tap()
            XCTAssertTrue(displayed.waitForExistence(timeout: 5))
            XCTAssertEqual(displayed.label, "Value: 12" + (kind == "pie" ? " percent" : ""), "Only saving the deliberate edit changes the displayed value.")
            XCTAssertEqual(app.staticTexts["reviewStatus-0"].label, "Unverified")
            reveal(confirm); confirm.tap()
            let reconfirmation = XCTNSPredicateExpectation(predicate: confirmed, object: app.staticTexts["reviewStatus-0"])
            let reconfirmedResult = XCTWaiter.wait(for: [reconfirmation], timeout: 5)
            if reconfirmedResult != .completed { print("REVIEW RECONFIRM FAILURE:\n" + app.debugDescription) }
            XCTAssertEqual(reconfirmedResult, .completed)
            let reject = app.buttons["rejectValue-0"]; reveal(reject); reject.tap()
            XCTAssertEqual(app.staticTexts["reviewStatus-0"].label, "Rejected")
            XCTAssertFalse(app.staticTexts["trustedAvailability"].label.hasPrefix("Chart verified"))
            let evidence = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Evidence for ")).firstMatch; reveal(evidence); evidence.tap()
            let support = app.staticTexts["Limited supporting evidence"]; reveal(support)
            XCTAssertTrue(support.isHittable)
            XCTAssertTrue(app.buttons["Advanced Technical Details"].exists)
            XCTAssertTrue(app.staticTexts["evidenceAgreement-0"].exists)
            let crop = app.buttons["Optional source-region image"].firstMatch; reveal(crop); crop.tap()
            XCTAssertTrue(app.images["sourceRegionImage"].waitForExistence(timeout: 10))
            reveal(app.images["sourceRegionImage"])
            let cropShot = XCTAttachment(screenshot: app.screenshot()); cropShot.name = "Source region - " + kind; cropShot.lifetime = .keepAlways; add(cropShot)
            reveal(evidence); evidence.tap()

            let count = kind == "line" ? 4 : 3
            if kind == "pie" {
                XCTAssertTrue(app.staticTexts["reviewPieUnits"].exists)
                XCTAssertFalse(app.textFields["reviewUnit"].exists)
                XCTAssertTrue(app.staticTexts["chartValidation"].label.contains("not 100"))
                for (index, text) in ["20", "30", "50"].enumerated() {
                    let edit = app.buttons["editValue-\(index)"]; reveal(edit); edit.tap()
                    let field = valueField(index)
                    XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap()
                    let old = field.value as? String ?? ""
                    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count) + text)
                    if app.buttons["saveValueEdit"].isEnabled { app.buttons["saveValueEdit"].tap() }
                    else { app.buttons["Cancel"].tap() }
                    let display = app.staticTexts["reviewDisplayedValue-\(index)"]
                    XCTAssertTrue(display.waitForExistence(timeout: 5))
                    XCTAssertEqual(display.label, "Value: " + text + " percent")
                }
            }
            for index in 0..<count {
                let resolve = app.buttons["resolveValue-\(index)"]; if resolve.exists { reveal(resolve); resolve.tap() }
                let resolved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Unverified"), object: app.staticTexts["reviewStatus-\(index)"])
                XCTAssertEqual(XCTWaiter.wait(for: [resolved], timeout: 5), .completed)
                let confirm = app.buttons["confirmValue-\(index)"]; reveal(confirm); confirm.tap()
                let done = XCTNSPredicateExpectation(predicate: confirmed, object: app.staticTexts["reviewStatus-\(index)"])
                let outcome = XCTWaiter.wait(for: [done], timeout: 5)
                if outcome != .completed { print("FINAL POINT CONFIRM FAILURE:\n" + app.debugDescription) }
                XCTAssertEqual(outcome, .completed)
            }
            XCTAssertTrue(app.staticTexts["trustedAvailability"].label.hasPrefix("Chart verified"))
            reveal(app.staticTexts["trustedAvailability"])
            XCTAssertTrue(app.staticTexts["trustedAvailability"].isHittable)
            XCTAssertTrue(app.staticTexts["verificationProgress"].label.contains("\(count) confirmed"))
            let back = app.navigationBars["Review and Verify"].buttons.element(boundBy: 0)
            back.tap()
            let returnedToAnalysis = app.buttons["reviewAndVerify"].waitForExistence(timeout: 5)
            if !returnedToAnalysis { print("BACK NAVIGATION FAILURE:\n" + app.debugDescription) }
            XCTAssertTrue(returnedToAnalysis)
            reveal(review); review.tap()
            XCTAssertTrue(app.staticTexts["trustedAvailability"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["trustedAvailability"].label.hasPrefix("Chart verified"), "Review changes must survive back navigation within the import preview")
            print("REVIEW UI|" + kind + "|edit, confirm, revoke and reject passed\n" + app.debugDescription)
            let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Review - " + kind; shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }
    @MainActor
    func testReviewMetadataAndInvalidInput() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--import-fixture=vertical"]; app.launchArguments += ["--skip-onboarding", "--ui-test-library=" + UUID().uuidString]; app.launch()
        func reveal(_ element: XCUIElement) {
            for _ in 0..<22 {
                if element.isHittable { return }
                if element.exists, element.frame.midY < app.frame.midY { app.swipeDown() }
                else { app.swipeUp() }
            }
        }
        func field(_ identifier: String) -> XCUIElement {
            let textField = app.textFields[identifier]
            return textField.exists ? textField : app.textViews[identifier]
        }
        func replace(_ identifier: String, with text: String) {
            let anchor = app.staticTexts[identifier == "reviewTitle" || identifier == "reviewUnit" ? "chartSummary" : "reviewStatus-0"]
            reveal(anchor)
            if identifier == "reviewLabel-0", !field(identifier).exists {
                let editLabel = app.buttons["editLabel-0"]; reveal(editLabel); editLabel.tap()
            }
            let element = field(identifier)
            for _ in 0..<16 { if element.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(element.isHittable, "An editable field must be reachable by vertical scrolling")
            // Tap at the end of the last line, then replace the entire existing draft.
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.95)).tap()
            let old = element.value as? String ?? ""
            let placeholder = element.placeholderValue ?? ""
            let count = old == placeholder ? 0 : old.count
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: count) + text)
            app.buttons["Done Editing"].tap()
            if !text.isEmpty { XCTAssertEqual(element.value as? String, text) }
        }
        let start = app.buttons["importChart"]; reveal(start); start.tap()
        XCTAssertTrue(app.staticTexts["importReady"].waitForExistence(timeout: 10))
        let analyze = app.buttons["analyzeChart"]; reveal(analyze); analyze.tap()
        XCTAssertTrue(app.staticTexts["analysisResult"].waitForExistence(timeout: 30))
        let review = app.buttons["reviewAndVerify"]; reveal(review); review.tap()
        let details = app.buttons["editChartDetails"]; reveal(details); details.tap()
        XCTAssertTrue(field("reviewTitle").waitForExistence(timeout: 5))
        let resolve = app.buttons["resolveValue-0"]; if resolve.exists { reveal(resolve); resolve.tap() }
        let confirm = app.buttons["confirmValue-0"]; reveal(confirm); confirm.tap()
        XCTAssertEqual(app.staticTexts["reviewStatus-0"].label, "Confirmed by you")
        replace("reviewTitle", with: "")
        XCTAssertEqual(app.staticTexts["reviewStatus-0"].label, "Unverified")
        XCTAssertTrue(app.staticTexts["chartValidation"].label.contains("title"))
        replace("reviewTitle", with: "Community results")
        replace("reviewUnit", with: "USD")
        replace("reviewLabel-0", with: "Beta")
        XCTAssertTrue(app.staticTexts["rowValidation-0"].label.contains("duplicated"))
        XCTAssertTrue(app.staticTexts["verificationProgress"].label.contains("need correction"))
        reveal(confirm); confirm.tap()
        XCTAssertNotEqual(app.staticTexts["reviewStatus-0"].label, "Confirmed by you")
        replace("reviewLabel-0", with: "")
        XCTAssertTrue(app.staticTexts["rowValidation-0"].label.contains("Enter a label"))
        replace("reviewLabel-0", with: "Corrected label")
        func editValue(_ text: String, save: Bool) {
            let edit = app.buttons["editValue-0"]; reveal(edit); edit.tap()
            let value = field("reviewValue-0")
            XCTAssertTrue(value.waitForExistence(timeout: 5)); value.tap()
            let previous = value.value as? String ?? ""
            value.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count) + text)
            let saveButton = app.buttons["saveValueEdit"]
            if save { XCTAssertTrue(saveButton.isEnabled); saveButton.tap() }
            else { XCTAssertFalse(saveButton.isEnabled); app.buttons["Cancel"].tap() }
        }
        let beforeInvalidDraft = app.staticTexts["reviewDisplayedValue-0"].label
        editValue("", save: false)
        XCTAssertEqual(app.staticTexts["reviewDisplayedValue-0"].label, beforeInvalidDraft)
        XCTAssertEqual(app.staticTexts["reviewStatus-0"].label, "Unverified")
        editValue("12x", save: false)
        XCTAssertEqual(app.staticTexts["reviewDisplayedValue-0"].label, beforeInvalidDraft)
        XCTAssertNotEqual(app.staticTexts["reviewStatus-0"].label, "Confirmed by you")
        editValue("-5.25", save: true)
        reveal(confirm); confirm.tap()
        let verified = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Confirmed by you"), object: app.staticTexts["reviewStatus-0"])
        XCTAssertEqual(XCTWaiter.wait(for: [verified], timeout: 5), .completed)
        XCTAssertFalse(app.staticTexts["trustedAvailability"].label.hasPrefix("Chart verified"))
        print("METADATA UI|title, units, label, invalid/missing inputs and confirmation checked\n" + app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Review validation"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor
    func testAnalysisResultsRemainUnverified() throws {
        continueAfterFailure = false
        for kind in ["vertical", "horizontal", "line", "pie"] {
            let app = XCUIApplication()
            app.launchArguments = ["--import-fixture=" + kind]
            app.launchArguments += ["--skip-onboarding", "--ui-test-library=" + UUID().uuidString]; app.launch()
            let importButton = app.buttons["importChart"]
            for _ in 0..<10 {
                if importButton.isHittable { break }
                app.swipeUp()
            }
            importButton.tap()
            XCTAssertTrue(app.staticTexts["importReady"].waitForExistence(timeout: 10))
            let analyze = app.buttons["analyzeChart"]
            for _ in 0..<16 {
                if analyze.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(analyze.isHittable)
            analyze.tap()
            XCTAssertTrue(app.staticTexts["analysisResult"].waitForExistence(timeout: 30))
            let preview = app.buttons["Preview unverified estimates"]
            for _ in 0..<12 { if preview.isHittable { break }; app.swipeUp() }
            XCTAssertTrue(preview.isHittable); preview.tap()
            let candidate = app.staticTexts["candidate-0"]
            for _ in 0..<12 {
                if candidate.isHittable { break }
                if candidate.frame.midY > app.frame.midY {
                    app.swipeUp()
                } else {
                    app.swipeDown()
                }
            }
            XCTAssertTrue(candidate.exists)
            XCTAssertTrue(candidate.isHittable, "The unverified result must be reachable on screen.")
            XCTAssertTrue(candidate.label.contains("Unverified"))
            XCTAssertTrue(app.staticTexts["detectedChartType"].exists)
            print("Analysis accessibility hierarchy:\n\(app.debugDescription)")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Analysis — " + kind
            shot.lifetime = .keepAlways
            add(shot)
            app.buttons["Done"].tap()
            app.terminate()
        }
    }
    @MainActor
    func testImportPickerAndCancellation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--skip-onboarding", "--ui-test-library=" + UUID().uuidString]; app.launch()
        XCTAssertTrue(app.staticTexts["ChartBridge"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Make sense of your charts."].exists)
        let button = app.buttons["importChart"]
        for _ in 0..<6 {
            if button.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(button.isHittable)
        print("ChartBridge accessibility hierarchy:\n\(app.debugDescription)")
        button.tap()
        let choose = app.buttons["chooseFile"]
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        for _ in 0..<6 {
            if choose.isHittable { break }
            app.swipeUp()
        }
        choose.tap()
        // iOS 26 can expose the native picker cancellation control as Other,
        // rather than Button. Its user-facing label and behavior are unchanged.
        let cancel = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Cancel")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(choose.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(button.waitForExistence(timeout: 3))
    }

    @MainActor
    func testSavedChartsAndPrivacyAreReachable() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments += ["--skip-onboarding", "--ui-test-library=" + UUID().uuidString]; app.launch()
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "Home — current simulator appearance"
        home.lifetime = .keepAlways
        add(home)

        let emptyState = app.staticTexts["savedChartsEmptyState"]
        for _ in 0..<10 {
            if emptyState.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(emptyState.isHittable)
        XCTAssertTrue(emptyState.label.contains("Keep the charts that matter"))
        XCTAssertTrue(app.tabBars.buttons["My Charts"].exists)

        let privacy = app.staticTexts["privacyStatement"]
        for _ in 0..<10 {
            if privacy.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(privacy.isHittable)
        XCTAssertTrue(privacy.label.contains("processed on this device"))
        XCTAssertTrue(privacy.label.contains("decide what to save or share"))
        print("Home lower-section accessibility hierarchy:\n\(app.debugDescription)")
        let lower = XCTAttachment(screenshot: app.screenshot())
        lower.name = "Saved charts and privacy"
        lower.lifetime = .keepAlways
        add(lower)
    }

    @MainActor
    func testImportedPreviewsAndFailure() throws {
        for kind in ["png", "jpeg", "pdf", "invalid", "malformed-pdf", "oversized"] {
            let app = XCUIApplication()
            app.launchArguments = ["--import-fixture=" + kind]
            app.launchArguments += ["--skip-onboarding", "--ui-test-library=" + UUID().uuidString]; app.launch()
            let button = app.buttons["importChart"]
            for _ in 0..<6 {
                if button.isHittable { break }
                app.swipeUp()
            }
            button.tap()
            let valid = ["png", "jpeg", "pdf"].contains(kind)
            let state = app.staticTexts[valid ? "importReady" : "importError"]
            XCTAssertTrue(state.waitForExistence(timeout: 10))
            if valid {
                XCTAssertEqual(state.label, "Ready to analyze")
                XCTAssertEqual(app.staticTexts["importVerificationGuidance"].label,
                    "Find values, then review and confirm them.")
            }
            if kind == "malformed-pdf" { XCTAssertTrue(state.label.contains("damaged or incomplete")) }
            if kind == "oversized" { XCTAssertTrue(state.label.contains("20 MB")) }
            print("Import accessibility hierarchy:\n\(app.debugDescription)")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "Import preview — " + kind
            shot.lifetime = .keepAlways
            add(shot)
            // Retry remains accessible by scrolling, even at AX5.
            let choose = app.buttons["chooseFile"]
            for _ in 0..<10 {
                if choose.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(choose.isHittable)
            app.buttons["Done"].tap()
            XCTAssertTrue(app.staticTexts["ChartBridge"].exists)
            app.terminate()
        }
    }
}
