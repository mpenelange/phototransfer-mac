import Foundation
import Testing
@testable import PhotoTransfer

@Suite("Import destinations")
struct ImportDestinationTests {
    @Test("Formats the import date as a stable local calendar folder name")
    func formatsDateFolder() throws {
        let date = try #require(
            Calendar(identifier: .gregorian).date(from: DateComponents(
                timeZone: TimeZone(secondsFromGMT: 0),
                year: 2026,
                month: 8,
                day: 18,
                hour: 12
            ))
        )

        #expect(ImportFolderNaming.folderName(
            for: date,
            timeZone: try #require(TimeZone(secondsFromGMT: 0))
        ) == "2026-08-18")
    }

    @Test("Recognizes a camera volume from its DCIM folder")
    func recognizesDCIMVolume() throws {
        let root = try TemporaryFolder()
        let dcim = try root.folder("dcim")

        #expect(VolumeDiscovery.containsDCIMFolder(on: root.url))
        #expect(
            VolumeDiscovery.preferredPhotoFolder(on: root.url).resolvingSymlinksInPath()
                == dcim.resolvingSymlinksInPath()
        )
    }

    @Test("Resolves a selected DCIM folder to its mounted volume")
    func resolvesContainingVolume() throws {
        let volume = URL(filePath: "/Volumes/CAMERA CARD", directoryHint: .isDirectory)
        let source = volume.appending(path: "DCIM/100NIKON", directoryHint: .isDirectory)

        #expect(VolumeDiscovery.containingVolume(for: source, candidates: [volume]) == volume)
        #expect(VolumeDiscovery.containingVolume(for: source, candidates: []) == volume)
        #expect(VolumeDiscovery.containingVolume(
            for: URL(filePath: "/Users/test/Pictures", directoryHint: .isDirectory),
            candidates: []
        ) == nil)
    }
}
