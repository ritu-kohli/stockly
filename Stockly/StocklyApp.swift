import SwiftUI
import SwiftData

@main
struct StocklyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Holding.self)
    }
}
