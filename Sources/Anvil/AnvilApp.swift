import SwiftUI

@main
struct AnvilApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Anvil")
            .frame(minWidth: 600, minHeight: 400)
    }
}
