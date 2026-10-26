import Foundation
import CryptoKit

enum ChartLibraryError: String, Error, LocalizedError, Sendable {
    case corrupt = "A saved chart is corrupt or invalid. Its file was retained."
    case incompatible = "This saved chart uses an unsupported schema. Its file was retained."
    case duplicate = "A chart with this identifier is already saved. Confirm replacement first."
    case conflict = "The saved chart changed. Reload the library before trying again."
    case missing = "The saved chart could not be found."
    case unsafeFile = "The local library contains an unsupported file or symbolic link."
    case tooLarge = "The chart exceeds the local library size limit."
    case invalidTitle = "Enter a nonempty chart title of at most 4,096 characters."
    case busy = "Another local change is in progress. Wait for it to finish, then try again."
    case storage = "The local operation could not finish. Existing saved data was not intentionally discarded. Try again when the device is unlocked and has available storage."
    var errorDescription: String? { rawValue }
}

struct SavedChartRecord: Codable, Equatable, Sendable {
    enum Origin: String, Codable, Sendable { case acceptedOCR, acceptedGeometry, userCorrection }
    struct Point: Codable, Equatable, Sendable {
        let label: String
        let order: Int
        let value: String
        let origin: Origin
        let explicitlyConfirmed: Bool
    }
    let schemaVersion: Int
    let id: UUID
    let title: String
    let kind: String
    let horizontalAxis: String
    let verticalAxis: String
    let unit: String
    let snapshotRevision: UInt64
    let createdAt: Date
    let modifiedAt: Date
    let points: [Point]

    init(snapshot: BarChart.TrustedSnapshot, createdAt: Date, modifiedAt: Date) {
        schemaVersion = 1; id = snapshot.id; title = snapshot.title; kind = snapshot.kind.rawValue
        horizontalAxis = snapshot.horizontalAxis; verticalAxis = snapshot.verticalAxis; unit = snapshot.unit
        snapshotRevision = snapshot.revision
        self.createdAt = createdAt; self.modifiedAt = modifiedAt
        points = snapshot.values.map { entry in
            let origin: Origin
            switch entry.confirmedCandidate.origin {
            case .ocr: origin = .acceptedOCR
            case .geometricEstimate: origin = .acceptedGeometry
            case .userCorrection: origin = .userCorrection
            }
            return .init(label: entry.label, order: entry.order, value: NSDecimalNumber(decimal: entry.value).stringValue,
                         origin: origin, explicitlyConfirmed: true)
        }
    }

    func matches(_ snapshot: BarChart.TrustedSnapshot) -> Bool {
        self == SavedChartRecord(snapshot: snapshot, createdAt: createdAt, modifiedAt: modifiedAt)
    }

    /// Replay persisted, validated explicit confirmations through the original
    /// engine. No decoded status or writable trusted-snapshot initializer exists.
    fileprivate func reopen() throws -> BarChart {
        guard schemaVersion == 1 else { throw ChartLibraryError.incompatible }
        guard let chartKind = ChartKind(rawValue: kind), (1...1_000).contains(points.count),
              points.map(\.order) == Array(points.indices), points.allSatisfy(\.explicitlyConfirmed),
              snapshotRevision >= UInt64(points.count * 2), snapshotRevision < UInt64.max - UInt64(points.count * 3 + 1),
              createdAt.timeIntervalSince1970.isFinite, modifiedAt.timeIntervalSince1970.isFinite,
              abs(createdAt.timeIntervalSince1970) < 1e12, abs(modifiedAt.timeIntervalSince1970) < 1e12,
              createdAt <= modifiedAt, title.count <= 4_096, points.allSatisfy({ $0.label.count <= 4_096 })
        else { throw ChartLibraryError.corrupt }
        do {
            var chart = try BarChart(id: id, initialRevision: snapshotRevision - UInt64(points.count * 2),
                kind: chartKind, title: title, horizontalAxis: horizontalAxis, verticalAxis: verticalAxis, unit: unit,
                source: SourceProvenance(fileName: "Saved chart; original file not retained", mediaType: "application/vnd.chartbridge.saved"),
                categories: points.map { ($0.label, $0.order) })
            for point in points {
                try Task.checkCancellation()
                switch point.origin {
                case .acceptedOCR: try chart.propose(at: point.order, text: point.value)
                case .acceptedGeometry: try chart.proposeEstimate(at: point.order, text: point.value)
                case .userCorrection: try chart.edit(at: point.order, text: point.value)
                }
                try chart.confirm(at: point.order)
            }
            _ = try chart.trustedSnapshot()
            return chart
        } catch is CancellationError { throw CancellationError() }
        catch { throw ChartLibraryError.corrupt }
    }
}

struct SavedChart: Identifiable, Sendable {
    let record: SavedChartRecord
    let digest: String
    var id: UUID { record.id }
}
struct ChartLibraryListing: Sendable {
    let charts: [SavedChart]
    let issues: [String]
}

protocol ChartFileWriting: Sendable {
    func write(_ data: Data, to url: URL) throws
}
struct AtomicChartFileWriter: ChartFileWriting {
    func write(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #endif
    }
}

/// Versioned, protected sandbox files. Checksums detect corruption, not hostile
/// same-sandbox tampering. JSON is not accepted as a chart-import format.
actor ChartLibrary {
    private struct Envelope: Codable {
        let record: SavedChartRecord
        let sha256: String
    }
    private let root: URL
    private let writer: any ChartFileWriting
    private let clock: @Sendable () -> Date
    static let maximumBytes = 2 * 1_024 * 1_024
    static let maximumRecords = 2_000
    init(directory: URL, writer: any ChartFileWriting = AtomicChartFileWriter(), clock: @escaping @Sendable () -> Date = { Date() }) {
        root = directory; self.writer = writer; self.clock = clock
    }
    static func applicationLibrary() throws -> ChartLibrary {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return ChartLibrary(directory: base.appendingPathComponent("ChartBridgeLibrary", isDirectory: true))
    }
    private func prepareDirectory() throws {
        guard root.isFileURL else { throw ChartLibraryError.unsafeFile }
        let fm = FileManager.default
        guard (try? fm.destinationOfSymbolicLink(atPath: root.path)) == nil else { throw ChartLibraryError.unsafeFile }
        if fm.fileExists(atPath: root.path) {
            let values = try root.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true else { throw ChartLibraryError.unsafeFile }
        } else {
            #if os(iOS)
            try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            #else
            try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            #endif
        }
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var directory = root; try directory.setResourceValues(values)
    }
    private func url(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".json") }
    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }
    private func digest(_ record: SavedChartRecord) throws -> String {
        SHA256.hash(data: try encoder().encode(record)).map { String(format: "%02x", $0) }.joined()
    }
    private func read(_ id: UUID) throws -> SavedChart {
        let file = url(id)
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: file.path)) == nil else { throw ChartLibraryError.unsafeFile }
        guard FileManager.default.fileExists(atPath: file.path) else { throw ChartLibraryError.missing }
        let properties = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard properties.isSymbolicLink != true, properties.isRegularFile == true else { throw ChartLibraryError.unsafeFile }
        guard let size = properties.fileSize, size > 0, size <= Self.maximumBytes else { throw ChartLibraryError.tooLarge }
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: Self.maximumBytes + 1) ?? Data()
            guard data.count <= Self.maximumBytes else { throw ChartLibraryError.tooLarge }
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
            let envelope = try decoder.decode(Envelope.self, from: data)
            guard envelope.record.schemaVersion == 1 else { throw ChartLibraryError.incompatible }
            guard envelope.record.id == id, try digest(envelope.record) == envelope.sha256 else { throw ChartLibraryError.corrupt }
            _ = try envelope.record.reopen()
            return .init(record: envelope.record, digest: envelope.sha256)
        } catch is CancellationError { throw CancellationError() }
        catch let error as ChartLibraryError { throw error }
        catch { throw ChartLibraryError.corrupt }
    }
    func list() throws -> ChartLibraryListing {
        try Task.checkCancellation()
        try prepareDirectory()
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard files.count <= Self.maximumRecords else { throw ChartLibraryError.tooLarge }
        var records: [SavedChart] = [], issues: [String] = []
        for file in files {
            try Task.checkCancellation()
            do {
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                      file.lastPathComponent == id.uuidString + ".json" else { throw ChartLibraryError.unsafeFile }
                records.append(try read(id))
            } catch is CancellationError { throw CancellationError() }
            catch {
                issues.append((error as? ChartLibraryError)?.rawValue ?? ChartLibraryError.storage.rawValue)
            }
        }
        records.sort { $0.record.modifiedAt == $1.record.modifiedAt ? $0.id.uuidString < $1.id.uuidString : $0.record.modifiedAt > $1.record.modifiedAt }
        return .init(charts: records, issues: issues)
    }
    func load(_ id: UUID) throws -> SavedChart { try Task.checkCancellation(); try prepareDirectory(); return try read(id) }
    func open(_ id: UUID, expectedDigest: String? = nil) throws -> BarChart {
        try Task.checkCancellation()
        try prepareDirectory()
        let saved = try read(id)
        if let expectedDigest, expectedDigest != saved.digest { throw ChartLibraryError.conflict }
        return try saved.record.reopen()
    }

    /// Idempotent user-facing Save. Changed records require an explicit update
    /// with a current digest; copies use a stable ID supplied by that one action.
    func store(_ snapshot: BarChart.TrustedSnapshot, intent: ChartSaveIntent = .save) throws -> SavedChart {
        try Task.checkCancellation()
        try prepareDirectory()
        if case .copy(let id) = intent {
            guard id != snapshot.id else { throw ChartLibraryError.duplicate }
            return try store(snapshot.copyForLibrary(id: id))
        }
        let existing: SavedChart
        do { existing = try read(snapshot.id) }
        catch ChartLibraryError.missing {
            if case .update = intent { throw ChartLibraryError.conflict }
            return try save(snapshot)
        }
        if case .update(let expected) = intent {
            guard existing.digest == expected else { throw ChartLibraryError.conflict }
            if existing.record.matches(snapshot) { return existing }
            return try save(snapshot, replacing: expected)
        }
        guard existing.record.matches(snapshot) else { throw ChartLibraryError.duplicate }
        return existing
    }

    @discardableResult func save(_ snapshot: BarChart.TrustedSnapshot, replacing expectedDigest: String? = nil) throws -> SavedChart {
        try Task.checkCancellation()
        try prepareDirectory()
        guard (try? FileManager.default.destinationOfSymbolicLink(atPath: url(snapshot.id).path)) == nil else { throw ChartLibraryError.unsafeFile }
        let existing = FileManager.default.fileExists(atPath: url(snapshot.id).path) ? try read(snapshot.id) : nil
        if let existing {
            guard let expectedDigest else { throw ChartLibraryError.duplicate }
            guard expectedDigest == existing.digest else { throw ChartLibraryError.conflict }
        } else if expectedDigest != nil { throw ChartLibraryError.conflict }
        if existing == nil {
            let count = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }.count
            guard count < Self.maximumRecords else { throw ChartLibraryError.tooLarge }
        }
        // Whole-second dates make the checksum canonical across encode/decode.
        let now = Date(timeIntervalSince1970: clock().timeIntervalSince1970.rounded(.down))
        let created = existing?.record.createdAt ?? now
        let record = SavedChartRecord(snapshot: snapshot, createdAt: created, modifiedAt: max(created, now))
        _ = try record.reopen()
        let hash = try digest(record)
        let data = try encoder().encode(Envelope(record: record, sha256: hash))
        guard data.count <= Self.maximumBytes else { throw ChartLibraryError.tooLarge }
        try Task.checkCancellation()
        do { try writer.write(data, to: url(snapshot.id)) }
        catch { throw ChartLibraryError.storage }
        return .init(record: record, digest: hash)
    }
    func rename(_ id: UUID, title: String, expectedDigest: String) throws -> SavedChart {
        try Task.checkCancellation()
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 4_096 else { throw ChartLibraryError.invalidTitle }
        try prepareDirectory()
        let existing = try read(id)
        guard existing.digest == expectedDigest else { throw ChartLibraryError.conflict }
        var chart = try existing.record.reopen()
        chart.updateTitle(title)
        // The UI explicitly confirms retaining these values under the new title.
        for index in chart.categories.indices { try chart.confirm(at: index) }
        return try save(chart.trustedSnapshot(), replacing: expectedDigest)
    }
    func delete(_ id: UUID, expectedDigest: String) throws {
        try Task.checkCancellation()
        try prepareDirectory()
        let existing = try read(id)
        guard existing.digest == expectedDigest else { throw ChartLibraryError.conflict }
        try Task.checkCancellation()
        do { try FileManager.default.removeItem(at: url(id)) }
        catch { throw ChartLibraryError.storage }
    }
}
