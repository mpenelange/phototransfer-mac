import Foundation
import Testing
@testable import PhotoTransfer

@Suite("App model transfers")
@MainActor
struct AppModelTests {
    #if DEBUG
    // The fixture delay is intentionally compiled out of release builds.
    @Test("Stopping between JPEG and NEF with deletion resumes only the remaining original")
    func resumesCancelledPair() async throws {
        let fixture = try PairFixture()
        let model = fixture.model(transferDelay: .seconds(1))
        model.deleteOriginals = true
        await model.scan()
        let group = try #require(model.photoGroups.first)
        #expect(group.files.count == 2)

        let transfer = Task { await model.transfer() }
        let deadline = ContinuousClock.now + .seconds(5)
        while model.transferProgress?.completedCount != 1 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(model.transferProgress?.completedCount == 1)
        model.cancelTransfer()
        await transfer.value

        #expect(model.transferSummary?.wasCancelled == true)
        #expect(model.transferSummary?.results.count == 1)
        let completed = try #require(model.transferSummary?.results.first?.source)
        let remaining = try #require(group.files.first { $0.url != completed }?.url)
        #expect(FileManager.default.fileExists(atPath: completed.path) == false)
        #expect(FileManager.default.fileExists(atPath: remaining.path))
        #expect(model.isImported(group) == false)
        model.setSelected(false, for: group)
        model.setSelected(true, for: group)
        #expect(model.selectedFiles.map(\.url) == [remaining])
        #expect(model.selectedByteCount == Int64(try Data(contentsOf: remaining).count))

        await model.transfer()
        #expect(model.transferSummary?.results.map(\.source) == [remaining])
        #expect(model.transferSummary?.failedCount == 0)
        #expect(model.isImported(group))
        #expect(model.selectedFiles.isEmpty)
        #expect(FileManager.default.fileExists(atPath: remaining.path) == false)
    }
    #endif

    @Test("A failed sibling succeeds on retry and completes its photo")
    func retryCompletesPair() async throws {
        let fixture = try PairFixture()
        let model = fixture.model()
        await model.scan()
        let group = try #require(model.photoGroups.first)
        let missing = try #require(group.files.first { $0.kind == .nef }?.url)
        let bytes = try Data(contentsOf: missing)
        try FileManager.default.removeItem(at: missing)

        await model.transfer()
        #expect(model.transferSummary?.failedCount == 1)
        #expect(model.isImported(group) == false)
        #expect(model.selectedFiles.map(\.url) == [missing])
        #expect(model.canRetryFailed)

        try bytes.write(to: missing)
        await model.retryFailedTransfer()
        #expect(model.transferSummary?.results.map(\.source) == [missing])
        #expect(model.transferSummary?.failedCount == 0)
        #expect(model.isImported(group))
        #expect(model.selectedFiles.isEmpty)
        #expect(model.selectedPhotoCount == 0)

        // An explicit re-selection of a fully imported photo still permits re-import.
        model.setSelected(true, for: group)
        #expect(Set(model.selectedFiles.map(\.url)) == Set(group.files.map(\.url)))

        // Completion state belongs to the scan, not to these source paths forever.
        await model.scan()
        #expect(model.importedPhotoGroupIDs.isEmpty)
        #expect(model.selectedFiles.count == 2)
    }
}

@MainActor
private struct PairFixture {
    let root: TemporaryFolder
    let source: URL
    let raw: URL
    let jpeg: URL
    let nefFile: URL
    let defaults: UserDefaults

    init() throws {
        root = try TemporaryFolder()
        source = try root.folder("source")
        raw = try root.folder("raw")
        jpeg = try root.folder("jpeg")
        nefFile = source.appending(path: "DSC_0001.NEF")
        try Data("raw bytes".utf8).write(to: nefFile)
        try Data("jpeg bytes".utf8).write(to: source.appending(path: "DSC_0001.JPG"))
        defaults = try #require(UserDefaults(suiteName: "PhotoTransferTests.\(UUID().uuidString)"))
        defaults.set(false, forKey: "newFilesOnly")
    }

    func model(transferDelay: Duration? = nil) -> AppModel {
        AppModel(
            defaults: defaults,
            historyDirectoryURL: root.url.appending(path: "history", directoryHint: .isDirectory),
            sourceURL: source,
            nefDestinationURL: raw,
            jpegDestinationURL: jpeg,
            transferDelay: transferDelay
        )
    }
}
