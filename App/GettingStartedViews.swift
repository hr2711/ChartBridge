import SwiftUI

struct OnboardingView: View {
    @State private var progress = OnboardingProgress()
    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.page) {
                    Text("Welcome to ChartBridge").font(.headline)
                    Text("Step \(progress.step.rawValue + 1) of 3").foregroundStyle(.secondary)
                    ProgressView(value: Double(progress.step.rawValue + 1), total: 3)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Getting started progress")
                    InformationCard {
                        Text(progress.step.title).font(ChartBridgeDesign.title)
                            .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                        Text(progress.step.detail).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(progress.step == .explore ? "Get Started" : "Continue") { progress.advance(); finishIfNeeded() }
                        .modifier(PrimaryAction()).frame(minHeight: 44)
                    Text("No account, personal chart, or Apple Intelligence is required. Try a sample from the home screen.")
                }
                .padding(ChartBridgeDesign.Spacing.page).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(ChartBridgeDesign.Colors.canvas)
            .toolbar { ToolbarItem(placement: .cancellationAction) {
                Button("Skip") { progress.skip(); finishIfNeeded() }.font(.body)
            } }
            .onChange(of: progress.step) { _, _ in headingFocused = true }
        }
    }

    private func finishIfNeeded() {
        if progress.completed {
            OnboardingPreferences.complete(in: .standard)
            dismiss()
        }
    }
}

struct SampleGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Explore a fictional chart. No personal file needed.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.listRowBackground(Color.clear)
                Section {
                    ForEach(ChartSample.allCases) { sample in
                        NavigationLink {
                            ImportPanel(sample: sample, embeddedInNavigation: true)
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: sample.kind.symbolName).foregroundStyle(ChartBridgeDesign.Colors.accent).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(sample.title).font(.headline)
                                    Text(sample.kind.rawValue).font(.subheadline).foregroundStyle(.secondary)
                                    Text(sample.scenario).font(.subheadline).foregroundStyle(.secondary)
                                }.fixedSize(horizontal: false, vertical: true)
                            }.padding(.vertical, 8)
                        }
                        .accessibilityLabel("Open " + sample.title + ", " + sample.kind.rawValue)
                    }
                } footer: { Text("Samples use the same analysis and review steps as your own charts. Values are never confirmed for you.") }
            }
            .listStyle(.insetGrouped).navigationTitle("Sample Charts").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct ChartHelpView: View {
    @State private var showWelcome = false
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ChartSectionHeading(title: "A little help goes a long way", subtitle: "Find answers for each step of your chart.")
                    Button("Getting Started", systemImage: "hand.wave") { showWelcome = true }.frame(minHeight: 44)
                }.listRowBackground(Color.clear)
                Section("Using ChartBridge") {
                    DisclosureGroup("Import and analyze a chart") {
                        Text("Choose a JPEG, PNG or unencrypted single-page PDF up to 20 MB. Simple bars, marked single-series lines and labeled circular pies are supported.")
                        Text(RecoveryTopic.analysis.guidance)
                    }
                    DisclosureGroup("Review and confirm values") {
                        Text("Check labels, units and values before confirming them. The main Confirm button accepts one named value at a time. Uncertain values must be resolved separately.")
                        Text(RecoveryTopic.verification.guidance)
                    }
                    DisclosureGroup("Save and reopen charts") {
                        Text("After verification, tap Save Chart. Reopen from Home or My Charts. Changing a saved chart requires Update Chart or Save a Separate Copy.")
                        Text("Share or Export creates a report; it does not save a chart in My Charts.")
                        Text(RecoveryTopic.storage.guidance)
                    }
                    DisclosureGroup("Listen and explore") {
                        Text("Play Summary reads a short explanation. Previous and Next explore individual values. With VoiceOver, read actions focus text instead of starting separate speech.")
                    }
                }
                Section("Your data and accessibility") {
                    DisclosureGroup("Privacy on this device") {
                        Text("Recognition, calculations and optional AI run on-device. Closing a preview discards its original file and unsaved review. Saved charts contain verified values, not source files, and are excluded from cloud backup.")
                        Text("You choose when to share. Copies outside ChartBridge are controlled by their destination.")
                    }
                    DisclosureGroup("Accessible by design") {
                        Text("Dynamic Type, VoiceOver, readable evidence and ordered point exploration offer nonvisual alternatives. Chart values are also available as text. Actual device accessibility validation is still ongoing.")
                    }
                    DisclosureGroup("Apple Intelligence explanations") { Text(RecoveryTopic.intelligence.guidance) }
                }
                Section {
                    Text("Recognition can be imperfect. ChartBridge does not support every chart or guarantee that extracted values are correct.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.listRowBackground(Color.clear)
            }
            .font(.body)
            .listStyle(.insetGrouped).navigationTitle("Help")
            .sheet(isPresented: $showWelcome) { OnboardingView() }
        }
    }
}
