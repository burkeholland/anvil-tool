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

    var path: String? {
        directoryURL?.path
    }

    init() {
        // Default to home directory
        self.directoryURL = FileManager.default.homeDirectoryForCurrentUser
    }

    func setDirectory(_ url: URL) {
        directoryURL = url
    }
}
