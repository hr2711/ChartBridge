// swift-tools-version: 6.0
import PackageDescription

// Host-only checks reuse production services, including real macOS Vision OCR.
// No simulator, app, third-party package or live model session is needed.
let package = Package(
    name: "ChartBridgeCoreChecks",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "ChartBridgeMath", path: ".", exclude: [
            "App", "ChartBridge.xcodeproj", "Docs", "UnitTests", "Tests",
            "TestCharts", "CoreTests", "DerivedData", "work", "README.md", "AGENTS.md",
            "Analysis/EvidenceImage.swift", "Analysis/AppleChartExplanationProvider.swift"
        ], sources: [
            "Domain/BarChart.swift", "Domain/ChartNumberFormat.swift", "Analysis/VisualInsightData.swift", "Analysis/ChartCalculations.swift",
            "Analysis/ChartExplanationService.swift", "Analysis/ChartExplorer.swift", "Analysis/ChartNarration.swift",
            "Analysis/SpeechPlayback.swift", "Analysis/ChartQuestionParser.swift", "Analysis/ChartQuestionAnswering.swift", "Persistence/ChartLibrary.swift",
            "Reports/ChartReport.swift", "Import/ChartImporter.swift", "Domain/GettingStarted.swift",
            "Samples/SampleChartRenderer.swift", "Domain/LibraryNavigation.swift", "Analysis/OCR.swift", "Analysis/ExtractionModels.swift",
            "Analysis/Raster.swift", "Analysis/BarExtractor.swift", "Analysis/LineExtractor.swift",
            "Analysis/PieExtractor.swift", "Analysis/ChartAnalyzer.swift"
        ]),
        .testTarget(name: "ChartBridgeMathTests", dependencies: ["ChartBridgeMath"], path: "CoreTests")
    ],
    swiftLanguageModes: [.v6]
)
