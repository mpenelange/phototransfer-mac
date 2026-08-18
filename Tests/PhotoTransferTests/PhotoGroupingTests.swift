import Foundation
import Testing
@testable import PhotoTransfer

@Suite("Photo grouping")
struct PhotoGroupingTests {
    @Test("Combines matching NEF and JPEG files into one selection")
    func combinesRawJPEGPair() {
        let folder = URL(fileURLWithPath: "/Volumes/CARD/DCIM/100NIKON", isDirectory: true)
        let nef = sourceFile("DSC_1234.NEF", in: folder, kind: .nef)
        let jpeg = sourceFile("dsc_1234.jpg", in: folder, kind: .jpeg)

        let groups = PhotoGrouping.groups(for: [nef, jpeg])

        #expect(groups.count == 1)
        #expect(groups[0].files.count == 2)
        #expect(groups[0].typeLabel == "NEF + JPG")
        #expect(groups[0].previewURL == jpeg.url)
    }

    @Test("Does not combine matching names from different camera folders")
    func keepsFoldersSeparate() {
        let firstFolder = URL(fileURLWithPath: "/Volumes/CARD/DCIM/100NIKON", isDirectory: true)
        let secondFolder = URL(fileURLWithPath: "/Volumes/CARD/DCIM/101NIKON", isDirectory: true)

        let groups = PhotoGrouping.groups(for: [
            sourceFile("DSC_1234.NEF", in: firstFolder, kind: .nef),
            sourceFile("DSC_1234.JPG", in: secondFolder, kind: .jpeg)
        ])

        #expect(groups.count == 2)
    }

    @Test("Keeps a sidecar or movie separate from a photo pair")
    func keepsOtherFilesSeparate() {
        let folder = URL(fileURLWithPath: "/Volumes/CARD/DCIM/100NIKON", isDirectory: true)

        let groups = PhotoGrouping.groups(for: [
            sourceFile("DSC_1234.NEF", in: folder, kind: .nef),
            sourceFile("DSC_1234.JPG", in: folder, kind: .jpeg),
            sourceFile("DSC_1234.MOV", in: folder, kind: .other)
        ])

        #expect(groups.count == 2)
        #expect(groups.map(\.files.count).sorted() == [1, 2])
    }

    private func sourceFile(_ name: String, in folder: URL, kind: MediaKind) -> SourceFile {
        SourceFile(url: folder.appending(path: name), kind: kind, byteCount: 100)
    }
}
