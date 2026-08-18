import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private enum DefaultsKey {
        static let sourceBookmark = "sourceBookmark"
        static let nefDestinationBookmark = "nefDestinationBookmark"
        static let jpegDestinationBookmark = "jpegDestinationBookmark"
        static let deleteOriginals = "deleteOriginals"
        static let verifyCopies = "verifyCopies"
        static let otherFilePolicy = "otherFilePolicy"
        static let ejectAfterTransfer = "ejectAfterTransfer"
    }

    private let scanner = FileScanner()
    private let transferEngine = TransferEngine()
    private let defaults = UserDefaults.standard

    private(set) var sourceGrant: FolderGrant?
    private(set) var nefDestinationGrant: FolderGrant?
    private(set) var jpegDestinationGrant: FolderGrant?
    private(set) var mountedVolumes: [MountedVolume] = []
    private(set) var scanResult: ScanResult?
    private(set) var transferProgress: TransferProgress?
    private(set) var transferSummary: TransferSummary?
    private(set) var isScanning = false
    private(set) var isTransferring = false
    private(set) var ejectionState: EjectionState = .idle
    var errorMessage: String?

    var deleteOriginals: Bool {
        didSet {
            defaults.set(deleteOriginals, forKey: DefaultsKey.deleteOriginals)
            if deleteOriginals { verifyCopies = true }
        }
    }

    var verifyCopies: Bool {
        didSet { defaults.set(verifyCopies, forKey: DefaultsKey.verifyCopies) }
    }

    var otherFilePolicy: OtherFilePolicy {
        didSet {
            defaults.set(otherFilePolicy.rawValue, forKey: DefaultsKey.otherFilePolicy)
            scanResult = nil
            transferSummary = nil
        }
    }

    var ejectAfterTransfer: Bool {
        didSet { defaults.set(ejectAfterTransfer, forKey: DefaultsKey.ejectAfterTransfer) }
    }

    var sourceURL: URL? { sourceGrant?.url }
    var nefDestinationURL: URL? { nefDestinationGrant?.url }
    var jpegDestinationURL: URL? { jpegDestinationGrant?.url }
    var importFolderName: String { ImportFolderNaming.folderName() }
    var effectiveNEFDestinationURL: URL? {
        nefDestinationURL?.appending(path: importFolderName, directoryHint: .isDirectory)
    }
    var effectiveJPEGDestinationURL: URL? {
        jpegDestinationURL?.appending(path: importFolderName, directoryHint: .isDirectory)
    }
    var isBusy: Bool { isScanning || isTransferring }
    var sourceVolumeURL: URL? {
        guard let sourceURL else { return nil }
        return VolumeDiscovery.containingVolume(
            for: sourceURL,
            candidates: mountedVolumes.map(\.url)
        )
    }
    var canEjectSource: Bool { sourceVolumeURL != nil }
    var canScan: Bool { sourceURL != nil && isBusy == false }
    var canTransfer: Bool {
        guard let scanResult else { return false }
        return scanResult.files.isEmpty == false
            && nefDestinationURL != nil
            && jpegDestinationURL != nil
            && isBusy == false
    }

    init() {
        deleteOriginals = defaults.bool(forKey: DefaultsKey.deleteOriginals)
        verifyCopies = defaults.object(forKey: DefaultsKey.verifyCopies) as? Bool ?? true
        otherFilePolicy = defaults.string(forKey: DefaultsKey.otherFilePolicy)
            .flatMap(OtherFilePolicy.init(rawValue:)) ?? .jpegDestination
        ejectAfterTransfer = defaults.bool(forKey: DefaultsKey.ejectAfterTransfer)
        sourceGrant = FolderAccessStore.restore(key: DefaultsKey.sourceBookmark)
        nefDestinationGrant = FolderAccessStore.restore(key: DefaultsKey.nefDestinationBookmark)
        jpegDestinationGrant = FolderAccessStore.restore(key: DefaultsKey.jpegDestinationBookmark)
        refreshVolumes()
    }

    func refreshVolumes() {
        mountedVolumes = VolumeDiscovery.mountedExternalVolumes()
    }

    func selectMountedVolume(_ volume: MountedVolume) {
        setSource(VolumeDiscovery.preferredPhotoFolder(on: volume.url))
    }

    func chooseSource() {
        guard let url = FolderAccessStore.chooseFolder(
            message: "Choose the SD card, camera volume, or DCIM folder",
            initialURL: sourceURL
        ) else { return }
        setSource(url)
    }

    func chooseNEFDestination() {
        guard let url = FolderAccessStore.chooseFolder(
            message: "Choose where NEF files should be saved",
            initialURL: nefDestinationURL
        ) else { return }
        nefDestinationGrant = saveGrant(url, key: DefaultsKey.nefDestinationBookmark)
        resetTransferState()
    }

    func chooseJPEGDestination() {
        guard let url = FolderAccessStore.chooseFolder(
            message: "Choose where JPEG files should be saved",
            initialURL: jpegDestinationURL
        ) else { return }
        jpegDestinationGrant = saveGrant(url, key: DefaultsKey.jpegDestinationBookmark)
        resetTransferState()
    }

    func scan() async {
        guard let sourceURL else { return }
        isScanning = true
        errorMessage = nil
        transferSummary = nil
        defer { isScanning = false }

        do {
            scanResult = try await scanner.scan(source: sourceURL, otherFilePolicy: otherFilePolicy)
        } catch {
            scanResult = nil
            errorMessage = error.localizedDescription
        }
    }

    func transfer() async {
        guard let sourceURL,
              let nefDestinationURL,
              let jpegDestinationURL,
              let scanResult,
              scanResult.files.isEmpty == false else { return }

        isTransferring = true
        errorMessage = nil
        transferSummary = nil
        ejectionState = .idle
        transferProgress = TransferProgress(
            completedCount: 0,
            totalCount: scanResult.files.count,
            currentFileName: "Preparing…",
            copiedByteCount: 0,
            totalByteCount: scanResult.totalByteCount
        )

        let request = TransferRequest(
            sourceRoot: sourceURL,
            files: scanResult.files,
            nefDestination: nefDestinationURL,
            jpegDestination: jpegDestinationURL,
            importFolderName: importFolderName,
            otherFilePolicy: otherFilePolicy,
            deleteOriginals: deleteOriginals,
            verifyCopies: verifyCopies
        )
        let summary = await transferEngine.transfer(request) { [weak self] progress in
            await MainActor.run {
                self?.transferProgress = progress
            }
        }

        transferSummary = summary
        if ejectAfterTransfer {
            if summary.isFullySuccessful {
                ejectSourceVolume()
            } else {
                ejectionState = .keptMounted("The card stayed mounted because the transfer had issues.")
            }
        }
        isTransferring = false
        if summary.failedCount > 0 || summary.cleanupFailedCount > 0 {
            var details: [String] = []
            if summary.failedCount > 0 {
                details.append("\(summary.failedCount) file(s) could not be transferred")
            }
            if summary.cleanupFailedCount > 0 {
                details.append("\(summary.cleanupFailedCount) copied original(s) could not be deleted")
            }
            errorMessage = details.joined(separator: "; ") + "."
        }
    }

    private func setSource(_ url: URL) {
        sourceGrant = saveGrant(url, key: DefaultsKey.sourceBookmark)
        scanResult = nil
        resetTransferState()
    }

    private func saveGrant(_ url: URL, key: String) -> FolderGrant {
        do {
            return try FolderAccessStore.save(url, key: key)
        } catch {
            errorMessage = "The folder was selected, but access could not be saved for the next launch: \(error.localizedDescription)"
            return FolderGrant(url: url)
        }
    }

    private func resetTransferState() {
        transferProgress = nil
        transferSummary = nil
        ejectionState = .idle
    }

    private func ejectSourceVolume() {
        guard let volume = sourceVolumeURL else {
            let message = "Transfer complete, but the source volume could not be identified for ejection."
            ejectionState = .failed(message)
            errorMessage = message
            return
        }

        let name = mountedVolumes.first(where: { $0.url == volume })?.name ?? volume.lastPathComponent
        ejectionState = .ejecting(name)
        do {
            try VolumeEjector.eject(volume)
            ejectionState = .ejected(name)
            refreshVolumes()
        } catch {
            let message = "Transfer complete, but \(name) could not be ejected: \(error.localizedDescription)"
            ejectionState = .failed(message)
            errorMessage = message
        }
    }
}
