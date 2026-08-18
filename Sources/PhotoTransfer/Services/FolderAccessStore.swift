import AppKit
import Foundation

@MainActor
final class FolderGrant {
    let url: URL
    private let hasSecurityScope: Bool

    init(url: URL) {
        self.url = url
        hasSecurityScope = url.startAccessingSecurityScopedResource()
    }

    deinit {
        if hasSecurityScope {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

@MainActor
enum FolderAccessStore {
    private static let defaults = UserDefaults.standard

    static func save(_ url: URL, key: String) throws -> FolderGrant {
        let data = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(data, forKey: key)
        return FolderGrant(url: url)
    }

    static func restore(key: String) -> FolderGrant? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var stale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &stale
        ) else { return nil }

        if stale, let refreshed = try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            defaults.set(refreshed, forKey: key)
        }
        return FolderGrant(url: url)
    }

    static func chooseFolder(message: String, initialURL: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = message
        panel.message = message
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = initialURL
        return panel.runModal() == .OK ? panel.url : nil
    }
}
