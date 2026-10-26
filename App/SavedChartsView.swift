import SwiftUI

@MainActor @Observable
final class ChartLibraryModel {
    private(set) var repository: ChartLibrary?
    private(set) var charts: [SavedChart] = []
    private(set) var issues: [String] = []
    private(set) var loading = false
    private(set) var saving = false
    var message = ""
    private var refreshID = UUID()

    init() {
        #if DEBUG
        // UI validation must never rename/delete the user's actual library.
        if let argument = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--ui-test-library=") }),
           let id = UUID(uuidString: String(argument.dropFirst("--ui-test-library=".count))) {
            repository = ChartLibrary(directory: FileManager.default.temporaryDirectory
                .appendingPathComponent("ChartBridge-UITests-" + id.uuidString, isDirectory: true))
            return
        }
        #endif
        do { repository = try ChartLibrary.applicationLibrary() }
        catch { message = ChartLibraryError.storage.rawValue }
    }
    func refresh() async {
        guard let repository else { return }
        let request = UUID(); refreshID = request; loading = true
        do {
            let listing = try await repository.list()
            try Task.checkCancellation()
            guard refreshID == request else { return }
            charts = listing.charts; issues = listing.issues; loading = false; message = ""
        } catch is CancellationError {
            if refreshID == request { loading = false }
        } catch {
            guard refreshID == request else { return }
            loading = false; message = (error as? ChartLibraryError)?.rawValue ?? ChartLibraryError.storage.rawValue
        }
    }
    func store(_ snapshot: BarChart.TrustedSnapshot, authorization: ReportAuthorization, intent: ChartSaveIntent = .save) async throws -> SavedChart {
        guard let repository else { throw ChartLibraryError.storage }
        guard !saving else { throw ChartLibraryError.busy }
        try authorization.validate(snapshot)
        saving = true
        defer { saving = false }
        let saved = try await repository.store(snapshot, intent: intent)
        charts.removeAll { $0.id == saved.id }; charts.append(saved)
        charts.sort { $0.record.modifiedAt == $1.record.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.record.modifiedAt > $1.record.modifiedAt }
        return saved
    }
    func rename(_ saved: SavedChart, title: String) async throws {
        guard let repository else { throw ChartLibraryError.storage }
        guard !saving else { throw ChartLibraryError.busy }
        saving = true
        defer { saving = false }
        _ = try await repository.rename(saved.id, title: title, expectedDigest: saved.digest)
        await refresh()
    }
    func delete(_ saved: SavedChart) async throws {
        guard let repository else { throw ChartLibraryError.storage }
        guard !saving else { throw ChartLibraryError.busy }
        saving = true
        defer { saving = false }
        try await repository.delete(saved.id, expectedDigest: saved.digest)
        await refresh()
    }
}

struct SavedChartRow: View {
    let saved: SavedChart
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ChartKind(rawValue: saved.record.kind)?.symbolName ?? "chart.bar")
                .font(.title3).foregroundStyle(ChartBridgeDesign.Colors.accent).frame(minWidth: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(saved.record.title).font(.headline).foregroundStyle(.primary)
                Text(saved.record.kind).font(.subheadline).foregroundStyle(.secondary)
                Text("Modified " + saved.record.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

struct SavedChartsView: View {
    @Environment(ChartLibraryModel.self) private var library
    @Environment(ChartNavigation.self) private var navigation
    @State private var search = ""
    @State private var renameTarget: SavedChart?
    @State private var deleteTarget: SavedChart?
    @State private var newTitle = ""
    @State private var action: LibraryAction?
    private struct LibraryAction: Identifiable {
        let id = UUID()
        let chart: SavedChart
        let title: String?
    }
    private var filtered: [SavedChart] {
        search.isEmpty ? library.charts : library.charts.filter {
            $0.record.title.localizedCaseInsensitiveContains(search) || $0.record.kind.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        List {
            if library.loading && library.charts.isEmpty { ProgressView("Loading charts…") }
            if !library.message.isEmpty { Section { Text(library.message) } }
            if !library.issues.isEmpty {
                Section {
                    ChartNotice(title: "Some charts need attention", message: "Your files were kept. Pull down to try again.")
                    DisclosureGroup("Show details") {
                        ForEach(Array(library.issues.enumerated()), id: \.offset) { _, issue in Text(issue) }
                    }
                }
            }
            if library.charts.isEmpty && !library.loading {
                Section {
                    EmptyState(title: "A home for your charts", message: "Save a chart after confirming its values. Reopen it here to explore or listen again.")
                        .padding(.vertical, 12)
                    Button("Import Chart", systemImage: "plus") { navigation.presentation = .importChart }.frame(minHeight: 44)
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                Section {
                    ForEach(filtered) { saved in
                        NavigationLink(value: saved.id) { SavedChartRow(saved: saved) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button("Delete", role: .destructive) { deleteTarget = saved }
                                Button("Rename") { beginRename(saved) }.tint(.blue)
                            }
                            .contextMenu {
                                Button("Rename", systemImage: "pencil") { beginRename(saved) }
                                Button("Delete", systemImage: "trash", role: .destructive) { deleteTarget = saved }
                            }
                    }
                } footer: { Text("Saved on this device. Original images and PDFs are not stored.") }
            }
        }
        .listStyle(.insetGrouped).navigationTitle("My Charts")
        .searchable(text: $search, prompt: "Search charts")
        .refreshable { await library.refresh() }
        .disabled(library.saving)
        .toolbar {
            if !library.charts.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button("Import Chart", systemImage: "plus") { navigation.presentation = .importChart }
                }
            }
        }
        .alert("Rename chart", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } }), presenting: renameTarget) { saved in
            TextField("Chart title", text: $newTitle)
            Button("Rename") { action = .init(chart: saved, title: newTitle); renameTarget = nil }
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newTitle.count > 4_096)
            Button("Cancel", role: .cancel) { renameTarget = nil }
        } message: { _ in Text("Only the title changes. Your confirmed values stay the same.") }
        .alert("Delete chart?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { saved in
            Button("Delete", role: .destructive) { action = .init(chart: saved, title: nil); deleteTarget = nil }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: { saved in Text("Delete “\(saved.record.title)” from this device? This cannot be undone. Shared copies are not deleted.") }
        .task { await library.refresh() }
        .task(id: action?.id) {
            guard let action else { return }
            do {
                if let title = action.title { try await library.rename(action.chart, title: title); library.message = "Chart renamed." }
                else { try await library.delete(action.chart); library.message = "Chart deleted." }
            } catch is CancellationError { return }
            catch { library.message = (error as? ChartLibraryError)?.rawValue ?? ChartLibraryError.storage.rawValue }
            guard !Task.isCancelled else { return }
            AccessibilityNotification.Announcement(library.message).post()
        }
    }
    private func beginRename(_ saved: SavedChart) { newTitle = saved.record.title; renameTarget = saved }
}

struct SavedChartDetail: View {
    let id: UUID
    let expectedDigest: String
    @Environment(ChartLibraryModel.self) private var library
    @Environment(ChartNavigation.self) private var navigation
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var chart: BarChart?
    @State private var speech = ChartSpeechService()
    @State private var authorization = ReportAuthorization()
    @State private var errorMessage = ""
    @State private var openRequest = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.page) {
                if let chart, let snapshot = try? chart.trustedSnapshot() {
                    Text(chart.title).font(ChartBridgeDesign.title).accessibilityAddTraits(.isHeader)
                    ChartStatus(title: "Verified chart", symbol: "checkmark.seal")
                    if textSize.isAccessibilitySize { InformationCard { SaveChartControls(snapshot: snapshot, authorization: authorization) } }
                    ChartInsightsSection(snapshot: snapshot, speech: speech, authorization: authorization).id(InsightKey(snapshot))
                } else if errorMessage.isEmpty { ProgressView("Validating saved chart…") }
                else {
                    ChartNotice(title: "Couldn't open this chart", message: errorMessage)
                    Button("Try Again", systemImage: "arrow.clockwise") { errorMessage = ""; openRequest = UUID() }.frame(minHeight: 44)
                }
            }
            .padding(ChartBridgeDesign.Spacing.page)
            .frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(ChartBridgeDesign.Colors.canvas)
        .navigationTitle("Chart").navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !textSize.isAccessibilitySize, let snapshot = try? chart?.trustedSnapshot() {
                SaveChartControls(snapshot: snapshot, authorization: authorization)
                    .padding(16).background(.bar)
            }
        }
        .task(id: openRequest) {
            do {
                guard let repository = library.repository else { throw ChartLibraryError.storage }
                let value = try await repository.open(id, expectedDigest: expectedDigest)
                guard !Task.isCancelled else { return }
                chart = value
                let snapshot = try value.trustedSnapshot()
                speech.synchronize(with: snapshot); authorization.synchronize(with: snapshot)
            } catch is CancellationError { return }
            catch { errorMessage = (error as? ChartLibraryError)?.rawValue ?? ChartLibraryError.corrupt.rawValue }
        }
        .onChange(of: library.charts.first(where: { $0.id == id })?.digest) { _, digest in
            if digest != expectedDigest {
                authorization.synchronize(with: nil); speech.synchronize(with: nil); chart = nil
                errorMessage = "This saved record changed or was deleted. Return to the library and reopen it."
            }
        }
        .onDisappear {
            speech.stop()
            // Pushing an insight keeps this validated record current. Popping
            // or replacing it must still revoke all derived/exported content.
            if !navigation.state.chartPath.contains(id) || library.charts.first(where: { $0.id == id })?.digest != expectedDigest {
                authorization.synchronize(with: nil)
                speech.synchronize(with: nil)
            }
        }
    }
}
