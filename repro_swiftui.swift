
import SwiftUI

struct TestView: View {
    let url: URL
    @State private var loadedURL: URL?

    var body: some View {
        Text("Loaded: \(loadedURL?.path ?? "nil")")
            .onAppear {
                loadedURL = url
                print("onAppear called for \(url.path)")
            }
            .onChange(of: url) { newURL in
                loadedURL = newURL
                print("onChange called for \(newURL.path)")
            }
    }
}
// This script is just for verification logic, can't run SwiftUI here.
// But based on SwiftUI rules:
// If a view's inputs change, body is recomputed.
// @State is PRESERVED.
// onAppear is NOT called again unless view was removed and re-added.
