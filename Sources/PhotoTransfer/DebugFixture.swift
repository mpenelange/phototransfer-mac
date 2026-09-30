#if DEBUG
import Foundation

/// Debug-only launch option for exercising the UI against a folder of test media without
/// going through open panels. Compiled out of release builds.
///
///     PhotoTransfer -PTFixtureRoot /path/to/fixtures [-PTFixtureTransferDelay 0.5]
///
/// `-PTFixtureTransferDelay` pauses for that many seconds after each file, to make
/// progress and cancellation observable with small test files.
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
    let transferDelay: Duration?

    /// Reads the fixture from the launch arguments. Clears the fixture settings domain, so call it once.
    static func fromLaunchArguments() -> DebugFixture? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-PTFixtureRoot"),
              arguments.indices.contains(index + 1) else { return nil }
        let delay = arguments.firstIndex(of: "-PTFixtureTransferDelay")
            .flatMap { arguments.indices.contains($0 + 1) ? Double(arguments[$0 + 1]) : nil }
            .map { Duration.milliseconds(Int($0 * 1_000)) }
        return DebugFixture(root: URL(fileURLWithPath: arguments[index + 1], isDirectory: true), transferDelay: delay)
    }

    private init?(root: URL, transferDelay: Duration?) {
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
        self.transferDelay = transferDelay
    }
}
#endif
