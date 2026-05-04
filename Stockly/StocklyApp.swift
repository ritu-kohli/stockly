import SwiftUI
// import SwiftData  // DISABLED — Supabase is source of truth

@main
struct StocklyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // .modelContainer(for: Holding.self, isUndoEnabled: false)  // DISABLED — SwiftData
    }
}
