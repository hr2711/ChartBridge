import SwiftUI

/// Small, semantic defaults shared by the home screen and its components.
enum ChartBridgeDesign {
    enum Colors {
        static let canvas = Color(uiColor: .systemGroupedBackground)
        static let surface = Color(uiColor: .secondarySystemGroupedBackground)
        static let outline = Color(uiColor: .separator)
        // Darker than system blue to preserve white-label contrast at standard text sizes.
        static let accent = Color(uiColor: .init { traits in
            if traits.accessibilityContrast == .high {
                return .init(red: 0, green: 0.24, blue: 0.52, alpha: 1)
            }
            return traits.userInterfaceStyle == .dark
                ? .init(red: 0.08, green: 0.37, blue: 0.76, alpha: 1)
                : .init(red: 0, green: 0.32, blue: 0.68, alpha: 1)
        })
    }

    enum Spacing {
        static let small: CGFloat = 8
        static let medium: CGFloat = 16
        static let page: CGFloat = 20
        static let section: CGFloat = 24
    }

    static let cardRadius: CGFloat = 16
    static let buttonRadius: CGFloat = 12
    static let title: Font = .title2.bold()
    static let sectionTitle: Font = .title3.weight(.semibold)
}

/// Keeps native button focus, activation, pressed state, and accessibility behavior.
struct PrimaryAction: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: ChartBridgeDesign.buttonRadius))
            .controlSize(.large)
            .tint(ChartBridgeDesign.Colors.accent)
    }
}

struct InformationCard<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.medium) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ChartBridgeDesign.Spacing.medium)
        .background(ChartBridgeDesign.Colors.surface,
                    in: RoundedRectangle(cornerRadius: ChartBridgeDesign.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: ChartBridgeDesign.cardRadius)
                .strokeBorder(ChartBridgeDesign.Colors.outline,
                              lineWidth: contrast == .increased ? 2 : 0)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
    }
}

struct EmptyState: View {
    let title: String
    let message: String
    var symbol = "chart.bar.doc.horizontal"

    var body: some View {
        VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.small) {
            Image(systemName: symbol).font(.title2).foregroundStyle(ChartBridgeDesign.Colors.accent)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct ChartSectionHeading: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(ChartBridgeDesign.sectionTitle).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

/// Symbol and words carry status independently of color.
struct ChartStatus: View {
    let title: String
    let symbol: String
    var body: some View {
        Label(title, systemImage: symbol).font(.subheadline.weight(.medium))
            .foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
    }
}

struct ChartNotice: View {
    let title: String
    let message: String
    var symbol = "exclamationmark.circle"
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ChartStatus(title: title, symbol: symbol)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
        }.fixedSize(horizontal: false, vertical: true)
    }
}

struct ChartActionRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.headline).foregroundStyle(ChartBridgeDesign.Colors.accent)
                .frame(minWidth: 28, minHeight: 24).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(.vertical, 8).contentShape(Rectangle()).accessibilityElement(children: .combine)
    }
}

extension ChartKind {
    var symbolName: String {
        switch self { case .verticalBar: "chart.bar"; case .horizontalBar: "chart.bar.xaxis"; case .line: "chart.xyaxis.line"; case .pie: "chart.pie" }
    }
}
