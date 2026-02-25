import Foundation
import Combine

final class WorkingDirectoryModel: ObservableObject {
    @Published private(set) var directoryURL: URL?

    var displayPath: String {
        guard let url = directoryURL else { return "No directory selected" }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    var projectName: String {
        directoryURL?.lastPathComponent ?? "Anvil"
    }

    var path: String? {
        directoryURL?.path
    }

    init() {
        // Start with no directory — the welcome screen handles first open
        self.directoryURL = nil
    }

    func setDirectory(_ url: URL) {
        directoryURL = url
    }
}
