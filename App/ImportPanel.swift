import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class ImportModel {
    enum State {
        case idle(String), loading, ready(ImportedChart), failed(String)
    }
    var state: State = .idle("Nothing is uploaded. Your file stays on this device.")
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private let importer = ChartImporter()

    func load(_ url: URL) {
        start { [importer] in try await importer.load(url: url) }
    }

    func loadSample(_ sample: ChartSample) {
        start { [importer] in
            let data = try await SampleChartRenderer().render(sample)
            try Task.checkCancellation()
            return try await importer.decode(data: data, fileName: sample.title + " (fictional sample).png")
        }
    }

    #if DEBUG
    func loadFixture(_ data: Data) {
        start { [importer] in try await importer.decode(data: data, fileName: "Synthetic test chart") }
    }
    #endif

    private func start(_ operation: @escaping @Sendable () async throws -> ImportedChart) {
        cancel()
        let id = UUID()
        requestID = id
        state = .loading
        task = Task {
            do {
                let chart = try await operation()
                try Task.checkCancellation()
                guard requestID == id else { return }
                state = .ready(chart)
                AccessibilityNotification.Announcement("Ready for Analysis. No values have been extracted.").post()
            } catch is CancellationError {
                // cancel() owns the visible state and invalidates this request.
            } catch {
                guard requestID == id else { return }
                state = .failed((error as? ImportFailure)?.errorDescription ?? "The file could not be imported. Please try again.")
                AccessibilityNotification.Announcement("Import failed. Choose another file to retry.").post()
            }
        }
    }

    func cancel() {
        requestID = UUID()
        task?.cancel()
        task = nil
        state = .idle("Import cancelled. Choose a file when you are ready.")
    }
}

struct ImportPanel: View {
    var sample: ChartSample? = nil
    var embeddedInNavigation = false
    @State private var loadedSample = false
    @State private var showsSampleReference = true
    @State private var model = ImportModel()
    @State private var choosingFile = false
    @State private var pickerMessage = ""
    #if DEBUG
    @State private var loadedSyntheticFixture = false
    #endif
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if embeddedInNavigation { workflow }
        else { NavigationStack { workflow } }
    }

    private var workflow: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.section) {
                if let sample, showsSampleReference {
                    ChartStatus(title: "Sample: " + sample.title, symbol: "sparkles")
                    DisclosureGroup("Sample reference values") {
                        Text(sample.reference)
                        Text("Fictional guidance only. Recognition may differ; review and confirm each value yourself.")
                    }.font(.subheadline)
                }
                switch model.state {
                case .idle(let message):
                    InformationCard {
                        EmptyState(title: "Start with a chart", message: "Choose a chart image or a single PDF page.", symbol: "doc.viewfinder")
                        Text("JPEG, PNG or single-page PDF · Up to 20 MB")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(message).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("importStatus")
                    }
                case .loading:
                    InformationCard {
                        ProgressView("Opening your chart…").accessibilityIdentifier("importLoading")
                        Button("Cancel Import") { model.cancel() }.frame(minHeight: 44)
                    }
                case .failed(let message):
                    InformationCard {
                        ChartStatus(title: "Couldn't open this chart", symbol: "exclamationmark.circle")
                        Text(message).font(.subheadline).accessibilityIdentifier("importError")
                    }
                case .ready(let chart):
                    InformationCard {
                        Text("Ready to analyze").font(ChartBridgeDesign.sectionTitle).accessibilityAddTraits(.isHeader).accessibilityIdentifier("importReady")
                        Text("Find values, then review and confirm them.").font(.subheadline).foregroundStyle(.secondary)
                            .accessibilityIdentifier("importVerificationGuidance")
                        if let image = UIImage(data: chart.previewPNG) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                                .accessibilityLabel("Chart preview. Values must still be reviewed and confirmed.")
                        }
                        Text(chart.source.fileName).font(.subheadline.weight(.medium)).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        DisclosureGroup("File details") {
                            Text(chart.source.mediaType + (chart.source.page.map { " · Page \($0)" } ?? ""))
                            Text("The original file is kept only for this preview. Save verified values later to keep them in My Charts.")
                        }.font(.subheadline)
                    }
                    InformationCard { AnalysisView(chart: chart).id(chart.id) }
                }
                if !pickerMessage.isEmpty { ChartNotice(title: "Try another file", message: pickerMessage) }
                if case .loading = model.state {} else {
                    if case .ready = model.state {
                        Button("Choose Another File", systemImage: "arrow.triangle.2.circlepath") {
                            pickerMessage = ""; choosingFile = true
                        }.frame(minHeight: 44).accessibilityIdentifier("chooseFile")
                    } else {
                        Button { pickerMessage = ""; choosingFile = true } label: {
                            Label("Choose a File", systemImage: "folder").frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .modifier(PrimaryAction()).accessibilityIdentifier("chooseFile")
                        .accessibilityHint("Opens Files for a JPEG, PNG or single-page PDF.")
                    }
                }
            }
            .padding(ChartBridgeDesign.Spacing.page)
            .frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(ChartBridgeDesign.Colors.canvas)
        .navigationTitle("Import Chart").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) {
            Button("Done") { model.cancel(); dismiss() }.font(.body)
        } }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.jpeg, .png, .pdf]) { result in
            switch result {
            case .success(let url):
                showsSampleReference = false
                pickerMessage = ""
                model.load(url)
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled {
                    pickerMessage = "The file could not be opened. Choose another file or try again."
                }
            }
        }
        .onChange(of: choosingFile) { _, presented in
            if !presented, case .idle = model.state {
                model.state = .idle("No file selected. Choose a file when you are ready.")
            }
        }
        // Pushing review must not discard the imported chart. Closing with
        // Done cancels explicitly; dismissal releases this in-memory model.
        .onDisappear { if case .loading = model.state { model.cancel() } }
        .task(id: sample) {
            guard let sample, !loadedSample else { return }
            loadedSample = true
            model.loadSample(sample)
        }
        #if DEBUG
        .task {
            // Synthetic input for UI tests; never compiled into Release.
            guard sample == nil else { return }
            guard let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--import-fixture=") }) else { return }
            guard !loadedSyntheticFixture else { return }
            loadedSyntheticFixture = true
            let kind = String(argument.dropFirst("--import-fixture=".count))
            let data: Data
            switch kind {
            case "png": data = ImportFixtures.image()
            case "jpeg": data = ImportFixtures.image(type: .jpeg)
            case "pdf": data = ImportFixtures.pdf()
            case "malformed-pdf": data = Data("%PDF-1.7\ntruncated".utf8)
            case "oversized": data = Data(repeating: 0, count: ChartImporter.maximumBytes + 1)
            case "vertical": data = ExtractionFixtures.make(kind: .verticalBar, variant: "negative").data
            case "horizontal": data = ExtractionFixtures.make(kind: .horizontalBar, variant: "negative").data
            case "line": data = ExtractionFixtures.make(kind: .line).data
            case "pie": data = ExtractionFixtures.make(kind: .pie).data
            default: data = Data("invalid".utf8)
            }
            model.loadFixture(data)
        }
        #endif
    }
}
