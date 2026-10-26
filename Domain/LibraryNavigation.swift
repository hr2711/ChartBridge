import Foundation

enum LibraryTab: String, Hashable, Sendable { case home, charts, help }

/// Small value state so cross-tab reopening is testable without a simulator.
struct LibraryNavigation: Equatable, Sendable {
    var tab: LibraryTab = .home
    var chartPath: [UUID] = []
    mutating func openChart(_ id: UUID) { tab = .charts; chartPath = [id] }
    mutating func showLibrary() { tab = .charts; chartPath = [] }
}

enum ChartSaveIntent: Sendable {
    case save
    case update(expectedDigest: String)
    case copy(id: UUID)
}
