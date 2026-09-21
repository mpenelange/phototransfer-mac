import CryptoKit
import Foundation

actor TransferEngine {
    enum TransferError: LocalizedError {
        case sourceAndDestinationOverlap
        case backupAndPrimaryDestinationOverlap
        case destinationUnavailable(String)
        case sourceUnavailable(String)
        case verificationFailed(String)

        var errorDescription: String? {
            switch self {
            case .sourceAndDestinationOverlap:
                "The source and destination folders must not contain one another."
            case .backupAndPrimaryDestinationOverlap:
                "The backup destination must be separate from the NEF and JPEG destinations."
            case .destinationUnavailable(let path):
                "The destination is unavailable: \(path)"
            case .sourceUnavailable(let path):
                "The source file is unavailable: \(path)"
            case .verificationFailed(let name):
                "Verification failed for \(name). The original was kept."
            }
        }
    }

    typealias ProgressHandler = @Sendable (TransferProgress) async -> Void

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func transfer(
        _ request: TransferRequest,
        progress: ProgressHandler? = nil
    ) async -> TransferSummary {
        do {
            try validate(request)
            try ensureDestination(importDestination(request.nefDestination, request: request))
            try ensureDestination(importDestination(request.jpegDestination, request: request))
            if let backupDestination = request.backupDestination {
                try ensureDestination(importDestination(backupDestination, request: request))
            }
        } catch {
            return TransferSummary(
                results: request.files.map {
                    TransferItemResult(
                        source: $0.url,
                        destination: nil,
                        backupDestination: nil,
                        outcome: .failed(error.localizedDescription),
                        originalDeleted: false
                    )
                },
                copiedByteCount: 0
            )
        }

        var results: [TransferItemResult] = []
        var copiedBytes: Int64 = 0
        let totalBytes = request.files.reduce(0) { $0 + $1.byteCount }

        for (index, file) in request.files.enumerated() {
            let result = transfer(file, request: request)
            results.append(result)
            switch result.outcome {
            case .copied, .backupFailed(_, primaryAlreadyPresent: false):
                copiedBytes += file.byteCount
            default:
                break
            }
            await progress?(TransferProgress(
                completedCount: index + 1,
                totalCount: request.files.count,
                currentFileName: file.url.lastPathComponent,
                copiedByteCount: copiedBytes,
                totalByteCount: totalBytes
            ))
        }

        return TransferSummary(results: results, copiedByteCount: copiedBytes)
    }

    private func transfer(_ file: SourceFile, request: TransferRequest) -> TransferItemResult {
        guard fileManager.fileExists(atPath: file.url.path) else {
            return failed(file, error: TransferError.sourceUnavailable(file.url.path))
        }

        guard let destinationRoot = destination(for: file.kind, request: request) else {
            return TransferItemResult(
                source: file.url,
                destination: nil,
                backupDestination: nil,
                outcome: .skipped,
                originalDeleted: false
            )
        }

        do {
            let verificationRequired = request.verifyCopies
                || request.deleteOriginals
                || request.backupDestination != nil
            let sourceDigest = verificationRequired ? try digest(of: file.url) : nil
            let primary = try copy(
                file.url,
                to: destinationRoot,
                sourceDigest: sourceDigest
            )

            var backupURL: URL?
            if let backupRoot = request.backupDestination {
                do {
                    let backup = try copy(
                        file.url,
                        to: importDestination(backupRoot, request: request),
                        sourceDigest: sourceDigest
                    )
                    backupURL = backup.url
                } catch {
                    return TransferItemResult(
                        source: file.url,
                        destination: primary.url,
                        backupDestination: nil,
                        outcome: .backupFailed(
                            "The primary copy is safe, but its backup failed: \(error.localizedDescription)",
                            primaryAlreadyPresent: primary.alreadyPresent
                        ),
                        originalDeleted: false
                    )
                }
            }

            do {
                let deleted = try deleteOriginalIfRequested(file.url, request: request)
                return TransferItemResult(
                    source: file.url,
                    destination: primary.url,
                    backupDestination: backupURL,
                    outcome: primary.alreadyPresent ? .alreadyPresent : .copied,
                    originalDeleted: deleted
                )
            } catch {
                return cleanupFailed(
                    file,
                    destination: primary.url,
                    backupDestination: backupURL,
                    error: error,
                    alreadyPresent: primary.alreadyPresent
                )
            }
        } catch {
            return failed(file, error: error)
        }
    }

    private struct CompletedCopy {
        let url: URL
        let alreadyPresent: Bool
    }

    private func copy(_ source: URL, to root: URL, sourceDigest: SHA256.Digest?) throws -> CompletedCopy {
        let destination = try availableDestination(for: source, in: root, sourceDigest: sourceDigest)

        switch destination {
        case .existing(let url):
            try reveal(url)
            return CompletedCopy(url: url, alreadyPresent: true)
        case .new(let url):
            let temporary = temporaryURL(for: url)
            defer { try? fileManager.removeItem(at: temporary) }
            try fileManager.copyItem(at: source, to: temporary)
            if let sourceDigest {
                guard try filesMatch(source, temporary, sourceDigest: sourceDigest) else {
                    throw TransferError.verificationFailed(source.lastPathComponent)
                }
            }
            try fileManager.moveItem(at: temporary, to: url)
            try reveal(url)
            return CompletedCopy(url: url, alreadyPresent: false)
        }
    }

    private func reveal(_ url: URL) throws {
        var visibleURL = url
        var values = URLResourceValues()
        values.isHidden = false
        try visibleURL.setResourceValues(values)
    }

    private enum DestinationChoice {
        case existing(URL)
        case new(URL)
    }

    private func availableDestination(
        for source: URL,
        in root: URL,
        sourceDigest: SHA256.Digest?
    ) throws -> DestinationChoice {
        let baseName = source.deletingPathExtension().lastPathComponent
        let pathExtension = source.pathExtension
        var sequence = 1

        while true {
            let suffix = sequence == 1 ? "" : "-\(sequence)"
            let fileName = pathExtension.isEmpty
                ? "\(baseName)\(suffix)"
                : "\(baseName)\(suffix).\(pathExtension)"
            let candidate = root.appending(path: fileName, directoryHint: .notDirectory)

            guard fileManager.fileExists(atPath: candidate.path) else {
                return .new(candidate)
            }
            if let sourceDigest, try filesMatch(source, candidate, sourceDigest: sourceDigest) {
                return .existing(candidate)
            }
            sequence += 1
        }
    }

    private func destination(for kind: MediaKind, request: TransferRequest) -> URL? {
        switch kind {
        case .nef: importDestination(request.nefDestination, request: request)
        case .jpeg: importDestination(request.jpegDestination, request: request)
        case .other:
            switch request.otherFilePolicy {
            case .jpegDestination: importDestination(request.jpegDestination, request: request)
            case .nefDestination: importDestination(request.nefDestination, request: request)
            case .skip: nil
            }
        }
    }

    private func importDestination(_ root: URL, request: TransferRequest) -> URL {
        root.appending(path: request.importFolderName, directoryHint: .isDirectory)
    }

    private func ensureDestination(_ url: URL) throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else { throw TransferError.destinationUnavailable(url.path) }
            return
        }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw TransferError.destinationUnavailable(url.path)
        }
    }

    private func validate(_ request: TransferRequest) throws {
        guard request.importFolderName.isEmpty == false,
              request.importFolderName != ".",
              request.importFolderName != "..",
              request.importFolderName.contains("/") == false else {
            throw TransferError.destinationUnavailable(request.importFolderName)
        }
        let source = request.sourceRoot.standardizedFileURL.path
        let destinations = [request.nefDestination, request.jpegDestination] + [request.backupDestination].compactMap { $0 }
        for destination in destinations {
            let path = destination.standardizedFileURL.path
            if overlaps(path, source) {
                throw TransferError.sourceAndDestinationOverlap
            }
        }

        if let backupDestination = request.backupDestination {
            let backup = backupDestination.standardizedFileURL.path
            for primary in [request.nefDestination, request.jpegDestination] {
                if overlaps(backup, primary.standardizedFileURL.path) {
                    throw TransferError.backupAndPrimaryDestinationOverlap
                }
            }
        }
    }

    private func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        lhs == rhs || lhs.hasPrefix(rhs + "/") || rhs.hasPrefix(lhs + "/")
    }

    private func deleteOriginalIfRequested(_ url: URL, request: TransferRequest) throws -> Bool {
        guard request.deleteOriginals else { return false }
        try fileManager.removeItem(at: url)
        return true
    }

    private func filesMatch(
        _ lhs: URL,
        _ rhs: URL,
        sourceDigest: SHA256.Digest? = nil
    ) throws -> Bool {
        let lhsValues = try lhs.resourceValues(forKeys: [.fileSizeKey])
        let rhsValues = try rhs.resourceValues(forKeys: [.fileSizeKey])
        guard lhsValues.fileSize == rhsValues.fileSize else { return false }
        return try (sourceDigest ?? digest(of: lhs)) == digest(of: rhs)
    }

    private func digest(of url: URL) throws -> SHA256.Digest {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), chunk.isEmpty == false {
            hasher.update(data: chunk)
        }
        return hasher.finalize()
    }

    private func temporaryURL(for destination: URL) -> URL {
        destination.deletingLastPathComponent().appending(
            path: ".\(destination.lastPathComponent).phototransfer-\(UUID().uuidString).part",
            directoryHint: .notDirectory
        )
    }

    private func failed(_ file: SourceFile, error: Error) -> TransferItemResult {
        TransferItemResult(
            source: file.url,
            destination: nil,
            backupDestination: nil,
            outcome: .failed(error.localizedDescription),
            originalDeleted: false
        )
    }

    private func cleanupFailed(
        _ file: SourceFile,
        destination: URL,
        backupDestination: URL?,
        error: Error,
        alreadyPresent: Bool
    ) -> TransferItemResult {
        TransferItemResult(
            source: file.url,
            destination: destination,
            backupDestination: backupDestination,
            outcome: .cleanupFailed(
                "The copy is verified, but the original could not be deleted: \(error.localizedDescription)",
                alreadyPresent: alreadyPresent
            ),
            originalDeleted: false
        )
    }
}
