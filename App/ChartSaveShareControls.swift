import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

/// The system requests bytes asynchronously. Check live verification both before
/// work and at delivery; opening a share/export UI cannot preserve revoked access.
struct VerifiedReportTransfer: Transferable, Sendable {
    let snapshot: BarChart.TrustedSnapshot
    let explanation: ChartExplanation?
    let authorization: ReportAuthorization
    let builder: ChartReportBuilder
    let isPDF: Bool
    private func data(pdf: Bool) async throws -> Data {
        try await authorization.validate(snapshot)
        let payload = try await builder.prepare(snapshot, explanation: explanation, includePDF: pdf)
        try Task.checkCancellation()
        return try await authorization.data(for: payload, pdf: pdf)
    }
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .pdf) { try await $0.data(pdf: true) }
            .exportingCondition { $0.isPDF }.suggestedFileName("ChartBridge-Report.pdf")
        DataRepresentation(exportedContentType: .plainText) { try await $0.data(pdf: false) }
            .exportingCondition { !$0.isPDF }.suggestedFileName("ChartBridge-Report.txt")
    }
}

/// Kept outside insights so saving is immediately available after verification,
/// independently of calculations, AI, speech, or report generation.
struct SaveChartControls: View {
    let snapshot: BarChart.TrustedSnapshot
    let authorization: ReportAuthorization
    @Environment(ChartLibraryModel.self) private var library
    @Environment(ChartNavigation.self) private var navigation
    @State private var request: Request?
    @State private var saving = false
    @State private var updateDigest: String?
    @State private var confirmUpdate = false
    @State private var lastSavedID: UUID?
    @State private var message = ""
    @State private var saveFailed = false
    private struct Request: Identifiable { let id = UUID(); let intent: ChartSaveIntent }
    private var existing: SavedChart? { library.charts.first { $0.id == snapshot.id } }
    private var isSaved: Bool { existing?.record.matches(snapshot) == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if saving { ProgressView("Saving chart…") }
            else if isSaved {
                HStack(alignment: .center) {
                    ChartStatus(title: "Saved", symbol: "checkmark.circle.fill").accessibilityIdentifier("chartSaved")
                    Spacer(minLength: 8)
                    saveOptions
                }
            } else {
                Text(existing == nil ? "Not saved yet" : "Changes not saved").font(.subheadline).foregroundStyle(.secondary)
                Button {
                    if let existing { updateDigest = existing.digest; confirmUpdate = true }
                    else { begin(.save) }
                } label: {
                    Label(existing == nil ? "Save Chart" : "Update Chart", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .modifier(PrimaryAction()).accessibilityIdentifier("saveVerifiedChart")
                .accessibilityHint("Keeps verified values in My Charts on this device. Sharing is separate.")
                if existing != nil { saveOptions }
            }
            if let id = lastSavedID ?? (isSaved ? snapshot.id : nil), navigation.state.tab != .charts {
                Button("View in My Charts", systemImage: "chart.bar.doc.horizontal") { navigation.openChart(id) }
                    .frame(minHeight: 44).accessibilityIdentifier("viewSavedChart")
            }
            if !message.isEmpty && (saveFailed || !isSaved || lastSavedID != snapshot.id) {
                Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("saveShareStatus")
            }
        }
        .disabled(saving || library.saving)
        .confirmationDialog("Update the saved chart?", isPresented: $confirmUpdate, titleVisibility: .visible) {
            Button("Update Existing Chart") {
                if let updateDigest { begin(.update(expectedDigest: updateDigest)) }
            }
            Button("Save a Separate Copy") { begin(.copy(id: UUID())) }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Updating replaces the previous saved values. A separate copy keeps both versions.") }
        .task(id: request?.id) {
            guard let request else { return }
            defer { saving = false }
            do {
                let saved = try await library.store(snapshot, authorization: authorization, intent: request.intent)
                guard !Task.isCancelled else { return }
                lastSavedID = saved.id
                message = saved.id == snapshot.id ? "Saved in My Charts." : "Separate copy saved in My Charts."
            } catch {
                guard !Task.isCancelled else { return }
                saveFailed = true
                message = (error as? LocalizedError)?.errorDescription ?? ChartLibraryError.storage.rawValue
            }
            AccessibilityNotification.Announcement(message).post()
        }
    }
    private var saveOptions: some View {
        Menu {
            Button("Save a Separate Copy", systemImage: "doc.on.doc") { begin(.copy(id: UUID())) }
        } label: {
            Label("Save Options", systemImage: "ellipsis.circle").labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
        }.accessibilityLabel("Save options").accessibilityHint("Save a separate copy without replacing the current saved chart.")
    }
    private func begin(_ intent: ChartSaveIntent) {
        guard !saving, !library.saving else { return }
        saving = true; saveFailed = false; message = ""; request = Request(intent: intent)
    }
}

struct ChartSaveShareControls: View {
    let snapshot: BarChart.TrustedSnapshot
    let explanation: ChartExplanation?
    let authorization: ReportAuthorization
    @State private var builder = ChartReportBuilder()
    @State private var exportingPDF = false
    @State private var exportingText = false
    @State private var message = ""

    private func transfer(pdf: Bool) -> VerifiedReportTransfer {
        .init(snapshot: snapshot, explanation: explanation, authorization: authorization, builder: builder, isPDF: pdf)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChartSectionHeading(title: "Share a report", subtitle: "Send verified values as a PDF or text file.")
            Menu {
                ShareLink(item: transfer(pdf: true), preview: SharePreview("ChartBridge report")) {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
                Button("Export PDF", systemImage: "doc.richtext") { exportingPDF = true }
                Button("Export Text", systemImage: "doc.plaintext") { exportingText = true }
            } label: {
                Label("Share or Export", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("reportActions")
            .accessibilityHint("Opens report actions. Saving your chart in My Charts is separate.")
            DisclosureGroup("Report details and help") {
                Text("Reports contain verified values, not the original file. Exporting leaves My Charts unchanged.")
                Text("PDF contains selectable text; full PDF/UA compliance has not been validated.")
                Text(RecoveryTopic.storage.guidance)
            }.font(.subheadline)
            if !message.isEmpty { Text(message).font(.subheadline) }
        }
        .fileExporter(isPresented: $exportingPDF, item: transfer(pdf: true), contentTypes: [.pdf],
            defaultFilename: "ChartBridge-Report.pdf", onCompletion: { complete($0, format: "PDF") },
            onCancellation: { message = "Export cancelled. Your library is unchanged." })
        .fileExporter(isPresented: $exportingText, item: transfer(pdf: false), contentTypes: [.plainText],
            defaultFilename: "ChartBridge-Report.txt", onCompletion: { complete($0, format: "Text") },
            onCancellation: { message = "Export cancelled. Your library is unchanged." })
    }
    private func complete(_ result: Result<URL, any Error>, format: String) {
        switch result {
        case .success: message = format + " report exported."
        case .failure: message = "Export could not finish. Keep this chart open, check available storage and try again."
        }
        AccessibilityNotification.Announcement(message).post()
    }
}
