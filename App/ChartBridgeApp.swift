import SwiftUI

@main
struct ChartBridgeApp: App {
    @State private var library = ChartLibraryModel()
    @State private var navigation = ChartNavigation()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(library)
                .environment(navigation)
        }
    }
}
