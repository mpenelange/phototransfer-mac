import CryptoKit
import Foundation

actor TransferEngine {
    enum TransferError: LocalizedError {
        case sourceAndDestinationOverlap
        case destinationUnavailable(String)
        case sourceUnavailable(String)
        case verificationFailed(String)

        var errorDescription: String? {
            switch self {
            case .sourceAndDestinationOverlap:
                "The source and destination folders must not contain one another."
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
        } catch {
            return TransferSummary(
                results: request.files.map {
                    TransferItemResult(
                        source: $0.url,
                        destination: nil,
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
            if case .copied = result.outcome {
                copiedBytes += file.byteCount
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
            return TransferItemResult(source: file.url, destination: nil, outcome: .skipped, originalDeleted: false)
        }

        do {
            let destination = try availableDestination(
                for: file.url,
                in: destinationRoot,
                verify: request.verifyCopies
            )

            switch destination {
            case .existing(let url):
                try reveal(url)
                do {
                    let deleted = try deleteOriginalIfRequested(file.url, request: request)
                    return TransferItemResult(
                        source: file.url,
                        destination: url,
                        outcome: .alreadyPresent,
                        originalDeleted: deleted
                    )
                } catch {
                    return cleanupFailed(file, destination: url, error: error, alreadyPresent: true)
                }

            case .new(let url):
                let temporary = temporaryURL(for: url)
                defer { try? fileManager.removeItem(at: temporary) }
                try fileManager.copyItem(at: file.url, to: temporary)
                if request.verifyCopies {
                    guard try filesMatch(file.url, temporary) else {
                        throw TransferError.verificationFailed(file.url.lastPathComponent)
                    }
                }
                try fileManager.moveItem(at: temporary, to: url)
                try reveal(url)
                do {
                    let deleted = try deleteOriginalIfRequested(file.url, request: request)
                    return TransferItemResult(
                        source: file.url,
                        destination: url,
                        outcome: .copied,
                        originalDeleted: deleted
                    )
                } catch {
                    return cleanupFailed(file, destination: url, error: error, alreadyPresent: false)
                }
            }
        } catch {
            return failed(file, error: error)
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

    private func availableDestination(for source: URL, in root: URL, verify: Bool) throws -> DestinationChoice {
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
            if verify, try filesMatch(source, candidate) {
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
        for destination in [request.nefDestination, request.jpegDestination] {
            let path = destination.standardizedFileURL.path
            if path == source || path.hasPrefix(source + "/") || source.hasPrefix(path + "/") {
                throw TransferError.sourceAndDestinationOverlap
            }
        }
    }

    private func deleteOriginalIfRequested(_ url: URL, request: TransferRequest) throws -> Bool {
        guard request.deleteOriginals else { return false }
        try fileManager.removeItem(at: url)
        return true
    }

    private func filesMatch(_ lhs: URL, _ rhs: URL) throws -> Bool {
        let lhsValues = try lhs.resourceValues(forKeys: [.fileSizeKey])
        let rhsValues = try rhs.resourceValues(forKeys: [.fileSizeKey])
        guard lhsValues.fileSize == rhsValues.fileSize else { return false }
        return try digest(of: lhs) == digest(of: rhs)
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
            outcome: .failed(error.localizedDescription),
            originalDeleted: false
        )
    }

    private func cleanupFailed(
        _ file: SourceFile,
        destination: URL,
        error: Error,
        alreadyPresent: Bool
    ) -> TransferItemResult {
        TransferItemResult(
            source: file.url,
            destination: destination,
            outcome: .cleanupFailed(
                "The copy is verified, but the original could not be deleted: \(error.localizedDescription)",
                alreadyPresent: alreadyPresent
            ),
            originalDeleted: false
        )
    }
}
