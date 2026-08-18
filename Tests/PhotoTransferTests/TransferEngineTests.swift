import Foundation
import Testing
@testable import PhotoTransfer

@Suite("Transfer engine")
struct TransferEngineTests {
    @Test("Routes NEF and JPEG files to separate destinations")
    func routesFileTypes() async throws {
        let root = try TemporaryFolder()
        let source = try root.folder("source")
        let raw = try root.folder("raw")
        let jpeg = try root.folder("jpeg")
        let nefFile = source.appending(path: "DSC_0001.NEF")
        let jpegFile = source.appending(path: "DSC_0001.JPG")
        try Data("raw bytes".utf8).write(to: nefFile)
        try Data("jpeg bytes".utf8).write(to: jpegFile)

        let request = TransferRequest(
            sourceRoot: source,
            files: [
                SourceFile(url: nefFile, kind: .nef, byteCount: 9),
                SourceFile(url: jpegFile, kind: .jpeg, byteCount: 10)
            ],
            nefDestination: raw,
            jpegDestination: jpeg,
            backupDestination: nil,
            importFolderName: "2026-08-18",
            otherFilePolicy: .jpegDestination,
            deleteOriginals: false,
            verifyCopies: true
        )

        let result = await TransferEngine().transfer(request)

        #expect(result.copiedCount == 2)
        #expect(FileManager.default.fileExists(atPath: dated(raw).appending(path: "DSC_0001.NEF").path))
        #expect(FileManager.default.fileExists(atPath: dated(jpeg).appending(path: "DSC_0001.JPG").path))
        #expect(FileManager.default.fileExists(atPath: nefFile.path))
    }

    @Test("Preserves a different file with the same name")
    func avoidsCollision() async throws {
        let root = try TemporaryFolder()
        let source = try root.folder("source")
        let raw = try root.folder("raw")
        let jpeg = try root.folder("jpeg")
        let sourceFile = source.appending(path: "image.jpg")
        try Data("new".utf8).write(to: sourceFile)
        let datedJPEG = try datedFolder(jpeg)
        try Data("old".utf8).write(to: datedJPEG.appending(path: "image.jpg"))

        let result = await TransferEngine().transfer(request(
            source: source,
            file: sourceFile,
            kind: .jpeg,
            raw: raw,
            jpeg: jpeg,
            delete: false
        ))

        #expect(result.copiedCount == 1)
        #expect(try Data(contentsOf: datedJPEG.appending(path: "image.jpg")) == Data("old".utf8))
        #expect(try Data(contentsOf: datedJPEG.appending(path: "image-2.jpg")) == Data("new".utf8))
    }

    @Test("Clears a hidden flag inherited by a copied file")
    func revealsCopiedFile() async throws {
        let root = try TemporaryFolder()
        let source = try root.folder("source")
        let raw = try root.folder("raw")
        let jpeg = try root.folder("jpeg")
        var sourceFile = source.appending(path: "image.nef")
        try Data("camera data".utf8).write(to: sourceFile)
        var hiddenValues = URLResourceValues()
        hiddenValues.isHidden = true
        try sourceFile.setResourceValues(hiddenValues)

        let result = await TransferEngine().transfer(request(
            source: source,
            file: sourceFile,
            kind: .nef,
            raw: raw,
            jpeg: jpeg,
            delete: false
        ))

        let destination = dated(raw).appending(path: "image.nef")
        #expect(result.copiedCount == 1)
        #expect(try destination.resourceValues(forKeys: [.isHiddenKey]).isHidden == false)
    }

    @Test("Deletes an original only after a verified copy")
    func safelyDeletesOriginal() async throws {
        let root = try TemporaryFolder()
        let source = try root.folder("source")
        let raw = try root.folder("raw")
        let jpeg = try root.folder("jpeg")
        let sourceFile = source.appending(path: "image.nef")
        try Data("camera data".utf8).write(to: sourceFile)

        let result = await TransferEngine().transfer(request(
            source: source,
            file: sourceFile,
            kind: .nef,
            raw: raw,
            jpeg: jpeg,
            delete: true
        ))

        #expect(result.copiedCount == 1)
        #expect(result.deletedCount == 1)
        #expect(FileManager.default.fileExists(atPath: sourceFile.path) == false)
        #expect(try Data(contentsOf: dated(raw).appending(path: "image.nef")) == Data("camera data".utf8))
    }

    @Test("Recognizes an identical destination and can clear the duplicate original")
    func handlesAlreadyPresentFile() async throws {
        let root = try TemporaryFolder()
        let source = try root.folder("source")
        let raw = try root.folder("raw")
        let jpeg = try root.folder("jpeg")
        let sourceFile = source.appending(path: "image.jpg")
        let bytes = Data("same photo".utf8)
        try bytes.write(to: sourceFile)
        let datedJPEG = try datedFolder(jpeg)
        try bytes.write(to: datedJPEG.appending(path: "image.jpg"))

        let result = await TransferEngine().transfer(request(
            source: source,
            file: sourceFile,
            kind: .jpeg,
            raw: raw,
            jpeg: jpeg,
            delete: true
        ))

        #expect(result.alreadyPresentCount == 1)
        #expect(result.deletedCount == 1)
        #expect(FileManager.default.fileExists(atPath: sourceFile.path) == false)
        #expect(FileManager.default.fileExists(atPath: datedJPEG.appending(path: "image-2.jpg").path) == false)
    }

    @Test("Rejects a destination nested inside the source")
    func rejectsOverlappingFolders() async throws {
        let root = try TemporaryFolder()
        let source = try root.folder("source")
        let raw = source.appending(path: "raw", directoryHint: .isDirectory)
        let jpeg = try root.folder("jpeg")
        let sourceFile = source.appending(path: "image.nef")
        try Data("camera data".utf8).write(to: sourceFile)

        let result = await TransferEngine().transfer(request(
            source: source,
            file: sourceFile,
            kind: .nef,
            raw: raw,
            jpeg: jpeg,
            delete: true
        ))

        #expect(result.failedCount == 1)
        #expect(result.deletedCount == 0)
        #expect(FileManager.default.fileExists(atPath: sourceFile.path))
        #expect(FileManager.default.fileExists(atPath: raw.path) == false)
    }

    @Test("Creates a verified backup before deleting the original")
    func createsBackupBeforeDeletion() async throws {
        let root = try TemporaryFolder()
        let source = try root.folder("source")
        let raw = try root.folder("raw")
        let jpeg = try root.folder("jpeg")
        let backup = try root.folder("backup")
        let sourceFile = source.appending(path: "image.nef")
        let bytes = Data("camera data".utf8)
        try bytes.write(to: sourceFile)

        let result = await TransferEngine().transfer(TransferRequest(
            sourceRoot: source,
            files: [SourceFile(url: sourceFile, kind: .nef, byteCount: Int64(bytes.count))],
            nefDestination: raw,
            jpegDestination: jpeg,
            backupDestination: backup,
            importFolderName: "2026-08-18",
            otherFilePolicy: .jpegDestination,
            deleteOriginals: true,
            verifyCopies: true
        ))

        #expect(result.copiedCount == 1)
        #expect(result.backupCopiedCount == 1)
        #expect(result.deletedCount == 1)
        #expect(FileManager.default.fileExists(atPath: sourceFile.path) == false)
        #expect(try Data(contentsOf: dated(raw).appending(path: "image.nef")) == bytes)
        #expect(try Data(contentsOf: dated(backup).appending(path: "image.nef")) == bytes)
    }

    @Test("Rejects a backup nested inside a primary destination")
    func rejectsOverlappingBackup() async throws {
        let root = try TemporaryFolder()
        let source = try root.folder("source")
        let raw = try root.folder("raw")
        let jpeg = try root.folder("jpeg")
        let backup = raw.appending(path: "backup", directoryHint: .isDirectory)
        let sourceFile = source.appending(path: "image.nef")
        try Data("camera data".utf8).write(to: sourceFile)

        let result = await TransferEngine().transfer(TransferRequest(
            sourceRoot: source,
            files: [SourceFile(url: sourceFile, kind: .nef, byteCount: 11)],
            nefDestination: raw,
            jpegDestination: jpeg,
            backupDestination: backup,
            importFolderName: "2026-08-18",
            otherFilePolicy: .jpegDestination,
            deleteOriginals: true,
            verifyCopies: true
        ))

        #expect(result.failedCount == 1)
        #expect(result.deletedCount == 0)
        #expect(FileManager.default.fileExists(atPath: sourceFile.path))
    }

    private func request(
        source: URL,
        file: URL,
        kind: MediaKind,
        raw: URL,
        jpeg: URL,
        delete: Bool
    ) -> TransferRequest {
        TransferRequest(
            sourceRoot: source,
            files: [SourceFile(url: file, kind: kind, byteCount: 10)],
            nefDestination: raw,
            jpegDestination: jpeg,
            backupDestination: nil,
            importFolderName: "2026-08-18",
            otherFilePolicy: .jpegDestination,
            deleteOriginals: delete,
            verifyCopies: true
        )
    }

    private func dated(_ root: URL) -> URL {
        root.appending(path: "2026-08-18", directoryHint: .isDirectory)
    }

    private func datedFolder(_ root: URL) throws -> URL {
        let folder = dated(root)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
