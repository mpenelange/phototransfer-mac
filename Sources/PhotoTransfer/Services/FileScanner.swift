import Foundation

actor FileScanner {
    enum ScanError: LocalizedError {
        case sourceUnavailable
        case cannotReadSource(String)

        var errorDescription: String? {
            switch self {
            case .sourceUnavailable: "The selected source is no longer available."
            case .cannotReadSource(let detail): "Could not read the source: \(detail)"
            }
        }
    }

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func scan(source: URL, otherFilePolicy: OtherFilePolicy) throws -> ScanResult {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ScanError.sourceUnavailable
        }

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isHiddenKey,
            .fileSizeKey,
            .isSymbolicLinkKey,
            .contentModificationDateKey
        ]
        let resourceKeys = Set(keys)
        guard let enumerator = fileManager.enumerator(
            at: source,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw ScanError.cannotReadSource("Folder enumeration failed.")
        }

        var files: [SourceFile] = []
        var skipped = 0

        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(forKeys: resourceKeys)
                guard values.isRegularFile == true,
                      values.isHidden != true,
                      values.isSymbolicLink != true,
                      url.lastPathComponent.hasPrefix("._") == false else {
                    continue
                }

                let kind = MediaKind.classify(url)
                if kind == .other, otherFilePolicy == .skip {
                    skipped += 1
                    continue
                }
                files.append(SourceFile(
                    url: url,
                    kind: kind,
                    byteCount: Int64(values.fileSize ?? 0),
                    modificationDate: values.contentModificationDate
                ))
            } catch {
                skipped += 1
            }
        }

        files.sort { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        return ScanResult(files: files, skippedFileCount: skipped)
    }
}
