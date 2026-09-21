import Foundation

actor ImportHistoryStore {
    private struct Fingerprint: Codable, Hashable {
        let relativePath: String
        let byteCount: Int64
        let modificationTime: Int64?
    }

    private let fileURL: URL
    private var importedFiles: Set<Fingerprint>

    init(fileManager: FileManager = .default, directoryURL: URL? = nil) {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = directoryURL ?? applicationSupport.appending(
            path: Bundle.main.bundleIdentifier ?? "PhotoTransfer",
            directoryHint: .isDirectory
        )
        fileURL = directory.appending(path: "ImportHistory.json", directoryHint: .notDirectory)
        importedFiles = Self.load(from: fileURL)
    }

    func newFiles(in files: [SourceFile], sourceRoot: URL) -> [SourceFile] {
        files.filter { importedFiles.contains(fingerprint(for: $0, sourceRoot: sourceRoot)) == false }
    }

    func record(_ files: [SourceFile], sourceRoot: URL) throws {
        importedFiles.formUnion(files.map { fingerprint(for: $0, sourceRoot: sourceRoot) })
        try save()
    }

    private func fingerprint(for file: SourceFile, sourceRoot: URL) -> Fingerprint {
        let rootPath = sourceRoot.standardizedFileURL.path
        let filePath = file.url.standardizedFileURL.path
        let relativePath = filePath.hasPrefix(rootPath + "/")
            ? String(filePath.dropFirst(rootPath.count + 1))
            : file.url.lastPathComponent
        return Fingerprint(
            relativePath: relativePath,
            byteCount: file.byteCount,
            modificationTime: file.modificationDate.map { Int64($0.timeIntervalSince1970.rounded()) }
        )
    }

    private func save() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(importedFiles)
        try data.write(to: fileURL, options: .atomic)
    }

    private static func load(from fileURL: URL) -> Set<Fingerprint> {
        guard let data = try? Data(contentsOf: fileURL),
              let history = try? JSONDecoder().decode(Set<Fingerprint>.self, from: data) else {
            return []
        }
        return history
    }
}
