#if os(macOS)
import SwiftUI

@main
struct AnvilApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
#else
// Minimal stub for non-macOS platforms (not a supported target).
@main
struct AnvilApp {
    static func main() {}
}
#endif
