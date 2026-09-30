#if DEBUG
import Foundation

/// Debug-only launch option for exercising the UI against a folder of test media without
/// going through open panels. Compiled out of release builds.
///
///     PhotoTransfer -PTFixtureRoot /path/to/fixtures
///
/// The root must contain `card/`, `nef/`, and `jpeg/` folders, and may contain `backup/`.
/// Settings use a separate `PhotoTransfer.fixture` domain that is cleared on each launch,
/// and import history lives in `history/` under the root, so a fixture run never reads or
/// writes the app's real preferences or history.
struct DebugFixture {
    let sourceURL: URL
    let nefDestinationURL: URL
    let jpegDestinationURL: URL
    let backupDestinationURL: URL?
    let defaults: UserDefaults
    let historyDirectoryURL: URL

    /// Reads the fixture from the launch arguments. Clears the fixture settings domain, so call it once.
    static func fromLaunchArguments() -> DebugFixture? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PTFixtureRoot"),
              arguments.indices.contains(index + 1) else { return nil }
        return DebugFixture(root: URL(fileURLWithPath: arguments[index + 1], isDirectory: true))
    }

    private init?(root: URL) {
        let fileManager = FileManager.default
        func folder(_ name: String) -> URL? {
            let url = root.appending(path: name, directoryHint: .isDirectory)
            var isDirectory: ObjCBool = false
            return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue ? url : nil
        }
        guard let card = folder("card"), let nef = folder("nef"), let jpeg = folder("jpeg") else {
            print("PTFixtureRoot must contain card/, nef/, and jpeg/ folders: \(root.path)")
            return nil
        }

        let suiteName = "PhotoTransfer.fixture"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        defaults.removePersistentDomain(forName: suiteName)

        sourceURL = card
        nefDestinationURL = nef
        jpegDestinationURL = jpeg
        backupDestinationURL = folder("backup")
        self.defaults = defaults
        historyDirectoryURL = root.appending(path: "history", directoryHint: .isDirectory)
    }
}
#endif
