import Foundation
import Testing
@testable import PhotoTransfer

@Suite("Import history")
struct ImportHistoryStoreTests {
    @Test("Filters a successfully recorded file")
    func filtersRecordedFile() async throws {
        let root = try TemporaryFolder()
        let fileURL = root.url.appending(path: "DCIM/100NIKON/DSC_0001.NEF")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("raw-data".utf8).write(to: fileURL)
        let file = SourceFile(
            url: fileURL,
            kind: .nef,
            byteCount: 8,
            modificationDate: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let historyDirectory = root.url.appending(path: "History", directoryHint: .isDirectory)
        let store = ImportHistoryStore(directoryURL: historyDirectory)

        #expect(await store.newFiles(in: [file], sourceRoot: root.url) == [file])
        try await store.record([file], sourceRoot: root.url)
        #expect(await store.newFiles(in: [file], sourceRoot: root.url).isEmpty)

        let restoredStore = ImportHistoryStore(directoryURL: historyDirectory)
        #expect(await restoredStore.newFiles(in: [file], sourceRoot: root.url).isEmpty)
    }

    @Test("Treats changed file contents as new metadata")
    func recognizesChangedMetadata() async throws {
        let root = try TemporaryFolder()
        let url = root.url.appending(path: "DSC_0001.NEF")
        let original = SourceFile(
            url: url,
            kind: .nef,
            byteCount: 100,
            modificationDate: Date(timeIntervalSince1970: 100)
        )
        let changed = SourceFile(
            url: url,
            kind: .nef,
            byteCount: 101,
            modificationDate: Date(timeIntervalSince1970: 101)
        )
        let store = ImportHistoryStore(
            directoryURL: root.url.appending(path: "History", directoryHint: .isDirectory)
        )

        try await store.record([original], sourceRoot: root.url)
        #expect(await store.newFiles(in: [changed], sourceRoot: root.url) == [changed])
    }
}
