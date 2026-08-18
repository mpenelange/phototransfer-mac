import Foundation
import Testing
@testable import PhotoTransfer

@Suite("File scanner")
struct FileScannerTests {
    @Test("Classifies NEF and JPEG extensions without regard to case")
    func classifiesFiles() async throws {
        let root = try TemporaryFolder()
        try Data("raw".utf8).write(to: root.url.appending(path: "one.NEF"))
        try Data("jpeg".utf8).write(to: root.url.appending(path: "two.jpeg"))
        try Data("movie".utf8).write(to: root.url.appending(path: "three.MOV"))

        let result = try await FileScanner().scan(source: root.url, otherFilePolicy: .jpegDestination)

        #expect(result.nefCount == 1)
        #expect(result.jpegCount == 1)
        #expect(result.otherCount == 1)
        #expect(result.totalByteCount == 12)
    }

    @Test("Skips unrecognized files when requested")
    func skipsOtherFiles() async throws {
        let root = try TemporaryFolder()
        try Data("raw".utf8).write(to: root.url.appending(path: "one.nef"))
        try Data("metadata".utf8).write(to: root.url.appending(path: "camera.dat"))

        let result = try await FileScanner().scan(source: root.url, otherFilePolicy: .skip)

        #expect(result.files.count == 1)
        #expect(result.skippedFileCount == 1)
    }
}

struct TemporaryFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "PhotoTransferTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func folder(_ name: String) throws -> URL {
        let folder = url.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}
