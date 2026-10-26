import SwiftUI

@MainActor @Observable
final class ChartNavigation {
    enum Presentation: String, Identifiable { case importChart, samples, welcome; var id: String { rawValue } }
    var state = LibraryNavigation()
    var presentation: Presentation?
    func openChart(_ id: UUID) { state.openChart(id); presentation = nil }
    func showLibrary() { state.showLibrary(); presentation = nil }
}

struct ContentView: View {
    @Environment(ChartLibraryModel.self) private var library
    @Environment(ChartNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.state.tab) {
            NavigationStack { home }
                .tabItem { Label("Home", systemImage: "house") }.tag(LibraryTab.home)
            NavigationStack(path: $navigation.state.chartPath) {
                SavedChartsView()
                    .navigationDestination(for: UUID.self) { id in
                        if let saved = library.charts.first(where: { $0.id == id }) {
                            SavedChartDetail(id: id, expectedDigest: saved.digest).id(saved.digest)
                        } else {
                            ContentUnavailableView("Chart unavailable", systemImage: "doc",
                                description: Text("It may have been deleted. Return to My Charts and refresh."))
                        }
                    }
            }
            .tabItem { Label("My Charts", systemImage: "chart.bar.doc.horizontal") }.tag(LibraryTab.charts)
            ChartHelpView()
                .tabItem { Label("Help", systemImage: "questionmark.circle") }.tag(LibraryTab.help)
        }
        .tint(ChartBridgeDesign.Colors.accent)
        .sheet(item: $navigation.presentation) { presentation in
            switch presentation {
            case .importChart: ImportPanel()
            case .samples: SampleGalleryView()
            case .welcome: OnboardingView()
            }
        }
        .task {
            var automatedCheck = false
            #if DEBUG
            automatedCheck = ProcessInfo.processInfo.arguments.contains("--skip-onboarding")
            #endif
            if !automatedCheck && !OnboardingPreferences.isComplete(in: .standard) { navigation.presentation = .welcome }
            await library.refresh()
        }
    }

    private var home: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Image(systemName: "chart.bar.doc.horizontal").font(.title2).foregroundStyle(ChartBridgeDesign.Colors.accent).accessibilityHidden(true)
                    Text("Make sense of your charts.").font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    Text("Bring a chart. Review its values. Discover what it shows.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button { navigation.presentation = .importChart } label: {
                        Label("Import Chart", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .modifier(PrimaryAction()).accessibilityIdentifier("importChart")
                    .accessibilityHint("Choose a JPEG, PNG or single-page PDF, then analyze it on this device.")
                    Button { navigation.presentation = .samples } label: {
                        Label("Try Sample Chart", systemImage: "chart.bar.xaxis").frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                }.padding(.vertical, 12)
            }
            .listRowBackground(Color.clear)
            Section {
                if library.loading && library.charts.isEmpty { ProgressView("Loading charts…") }
                else if library.charts.isEmpty {
                    EmptyState(title: "Keep the charts that matter",
                        message: "Your saved charts will appear here. Import a chart or try a sample to get started.")
                        .accessibilityIdentifier("savedChartsEmptyState").padding(.vertical, 8)
                } else {
                    ForEach(Array(library.charts.prefix(3))) { saved in
                        Button { navigation.openChart(saved.id) } label: {
                            HStack { SavedChartRow(saved: saved); Spacer(minLength: 8); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary).accessibilityHidden(true) }
                        }
                            .buttonStyle(.plain).frame(minHeight: 44)
                            .accessibilityHint("Opens this saved chart in My Charts.")
                    }
                }
            } header: {
                HStack {
                    Text("Recent charts"); Spacer()
                    Button { navigation.showLibrary() } label: {
                        Text("My Charts").font(.subheadline).frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
            }
            if !library.message.isEmpty { Section { Text(library.message) } }
            Section {
                Label("Private by design", systemImage: "lock")
                Text("Your charts are processed on this device. You decide what to save or share.")
                    .font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("privacyStatement")
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("ChartBridge").navigationBarTitleDisplayMode(.inline)
        .refreshable { await library.refresh() }
    }
}
