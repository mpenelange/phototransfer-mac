import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    private enum DefaultsKey {
        static let sourceBookmark = "sourceBookmark"
        static let nefDestinationBookmark = "nefDestinationBookmark"
        static let jpegDestinationBookmark = "jpegDestinationBookmark"
        static let backupDestinationBookmark = "backupDestinationBookmark"
        static let backupEnabled = "backupEnabled"
        static let deleteOriginals = "deleteOriginals"
        static let verifyCopies = "verifyCopies"
        static let otherFilePolicy = "otherFilePolicy"
        static let ejectAfterTransfer = "ejectAfterTransfer"
        static let newFilesOnly = "newFilesOnly"
    }

    private let scanner = FileScanner()
    private let transferEngine = TransferEngine()
    private let importHistory = ImportHistoryStore()
    private let defaults = UserDefaults.standard

    private(set) var sourceGrant: FolderGrant?
    private(set) var nefDestinationGrant: FolderGrant?
    private(set) var jpegDestinationGrant: FolderGrant?
    private(set) var backupDestinationGrant: FolderGrant?
    private(set) var mountedVolumes: [MountedVolume] = []
    private(set) var scanResult: ScanResult?
    private(set) var photoGroups: [PhotoGroup] = []
    private(set) var selectedPhotoGroupIDs: Set<PhotoGroupID> = []
    private(set) var transferProgress: TransferProgress?
    private(set) var transferSummary: TransferSummary?
    private(set) var isScanning = false
    private(set) var isTransferring = false
    private(set) var ejectionState: EjectionState = .idle
    private(set) var activeImportFolderName: String?
    var errorMessage: String?
    private var lastTransferRequest: TransferRequest?

    var deleteOriginals: Bool {
        didSet {
            defaults.set(deleteOriginals, forKey: DefaultsKey.deleteOriginals)
            if deleteOriginals { verifyCopies = true }
        }
    }

    var verifyCopies: Bool {
        didSet { defaults.set(verifyCopies, forKey: DefaultsKey.verifyCopies) }
    }

    var backupEnabled: Bool {
        didSet {
            defaults.set(backupEnabled, forKey: DefaultsKey.backupEnabled)
            if backupEnabled { verifyCopies = true }
            resetTransferState()
        }
    }

    var otherFilePolicy: OtherFilePolicy {
        didSet {
            defaults.set(otherFilePolicy.rawValue, forKey: DefaultsKey.otherFilePolicy)
            clearScan()
            resetTransferState()
        }
    }

    var ejectAfterTransfer: Bool {
        didSet { defaults.set(ejectAfterTransfer, forKey: DefaultsKey.ejectAfterTransfer) }
    }

    var newFilesOnly: Bool {
        didSet {
            defaults.set(newFilesOnly, forKey: DefaultsKey.newFilesOnly)
            clearScan()
            resetTransferState()
        }
    }

    var sourceURL: URL? { sourceGrant?.url }
    var nefDestinationURL: URL? { nefDestinationGrant?.url }
    var jpegDestinationURL: URL? { jpegDestinationGrant?.url }
    var backupDestinationURL: URL? { backupDestinationGrant?.url }
    var importFolderName: String { activeImportFolderName ?? ImportFolderNaming.folderName() }
    var effectiveNEFDestinationURL: URL? {
        nefDestinationURL?.appending(path: importFolderName, directoryHint: .isDirectory)
    }
    var effectiveJPEGDestinationURL: URL? {
        jpegDestinationURL?.appending(path: importFolderName, directoryHint: .isDirectory)
    }
    var effectiveBackupDestinationURL: URL? {
        backupDestinationURL?.appending(path: importFolderName, directoryHint: .isDirectory)
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
        selectedFiles.isEmpty == false
            && nefDestinationURL != nil
            && jpegDestinationURL != nil
            && (backupEnabled == false || backupDestinationURL != nil)
            && isBusy == false
    }
    var selectedPhotoCount: Int { selectedPhotoGroupIDs.count }
    var selectedFiles: [SourceFile] {
        photoGroups
            .filter { selectedPhotoGroupIDs.contains($0.id) }
            .flatMap(\.files)
    }
    var selectedByteCount: Int64 { selectedFiles.reduce(0) { $0 + $1.byteCount } }
    var failedTransferCount: Int { transferSummary?.failures.count ?? 0 }
    var canRetryFailed: Bool { failedTransferCount > 0 && isBusy == false }

    init() {
        deleteOriginals = defaults.bool(forKey: DefaultsKey.deleteOriginals)
        verifyCopies = defaults.object(forKey: DefaultsKey.verifyCopies) as? Bool ?? true
        backupEnabled = defaults.bool(forKey: DefaultsKey.backupEnabled)
        otherFilePolicy = defaults.string(forKey: DefaultsKey.otherFilePolicy)
            .flatMap(OtherFilePolicy.init(rawValue:)) ?? .jpegDestination
        ejectAfterTransfer = defaults.bool(forKey: DefaultsKey.ejectAfterTransfer)
        newFilesOnly = defaults.object(forKey: DefaultsKey.newFilesOnly) as? Bool ?? true
        sourceGrant = FolderAccessStore.restore(key: DefaultsKey.sourceBookmark)
        nefDestinationGrant = FolderAccessStore.restore(key: DefaultsKey.nefDestinationBookmark)
        jpegDestinationGrant = FolderAccessStore.restore(key: DefaultsKey.jpegDestinationBookmark)
        backupDestinationGrant = FolderAccessStore.restore(key: DefaultsKey.backupDestinationBookmark)
        if deleteOriginals || backupEnabled { verifyCopies = true }
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

    func chooseBackupDestination() {
        guard let url = FolderAccessStore.chooseFolder(
            message: "Choose where verified backup copies should be saved",
            initialURL: backupDestinationURL
        ) else { return }
        backupDestinationGrant = saveGrant(url, key: DefaultsKey.backupDestinationBookmark)
        resetTransferState()
    }

    func scan() async {
        guard let sourceURL else { return }
        isScanning = true
        errorMessage = nil
        resetTransferState()
        defer { isScanning = false }

        do {
            let scanned = try await scanner.scan(source: sourceURL, otherFilePolicy: otherFilePolicy)
            let files = if newFilesOnly {
                await importHistory.newFiles(in: scanned.files, sourceRoot: sourceURL)
            } else {
                scanned.files
            }
            let result = ScanResult(files: files, skippedFileCount: scanned.skippedFileCount)
            let groups = PhotoGrouping.groups(for: result.files)
            scanResult = result
            photoGroups = groups
            selectedPhotoGroupIDs = Set(groups.map(\.id))
        } catch {
            clearScan()
            errorMessage = error.localizedDescription
        }
    }

    func transfer() async {
        guard let sourceURL,
              let nefDestinationURL,
              let jpegDestinationURL,
              scanResult != nil else { return }

        let files = selectedFiles
        guard files.isEmpty == false else { return }

        let transferImportFolderName = ImportFolderNaming.folderName()
        let request = TransferRequest(
            sourceRoot: sourceURL,
            files: files,
            nefDestination: nefDestinationURL,
            jpegDestination: jpegDestinationURL,
            backupDestination: backupEnabled ? backupDestinationURL : nil,
            importFolderName: transferImportFolderName,
            otherFilePolicy: otherFilePolicy,
            deleteOriginals: deleteOriginals,
            verifyCopies: verifyCopies
        )
        await performTransfer(request)
    }

    func retryFailedTransfer() async {
        guard let previousRequest = lastTransferRequest,
              let transferSummary else { return }
        let failedURLs = Set(transferSummary.failures.map(\.source))
        let files = previousRequest.files.filter { failedURLs.contains($0.url) }
        guard files.isEmpty == false else { return }

        let request = TransferRequest(
            sourceRoot: previousRequest.sourceRoot,
            files: files,
            nefDestination: previousRequest.nefDestination,
            jpegDestination: previousRequest.jpegDestination,
            backupDestination: previousRequest.backupDestination,
            importFolderName: previousRequest.importFolderName,
            otherFilePolicy: previousRequest.otherFilePolicy,
            deleteOriginals: previousRequest.deleteOriginals,
            verifyCopies: previousRequest.verifyCopies
        )
        await performTransfer(request)
    }

    private func performTransfer(_ request: TransferRequest) async {
        isTransferring = true
        errorMessage = nil
        transferSummary = nil
        ejectionState = .idle
        activeImportFolderName = request.importFolderName
        lastTransferRequest = request
        transferProgress = TransferProgress(
            completedCount: 0,
            totalCount: request.files.count,
            currentFileName: "Preparing…",
            copiedByteCount: 0,
            totalByteCount: request.files.reduce(0) { $0 + $1.byteCount }
        )

        let summary = await transferEngine.transfer(request) { [weak self] progress in
            await MainActor.run {
                self?.transferProgress = progress
            }
        }

        transferSummary = summary
        let importedFiles = request.files.filter { file in
            guard let result = summary.results.first(where: { $0.source == file.url }) else { return false }
            return switch result.outcome {
            case .copied, .alreadyPresent:
                true
            default:
                false
            }
        }
        var historyError: Error?
        do {
            try await importHistory.record(importedFiles, sourceRoot: request.sourceRoot)
        } catch {
            historyError = error
        }
        if ejectAfterTransfer {
            if summary.isFullySuccessful {
                ejectSourceVolume()
            } else {
                ejectionState = .keptMounted("The card stayed mounted because the transfer had issues.")
            }
        }
        isTransferring = false
        var details: [String] = []
        if summary.failedCount > 0 {
            details.append("\(summary.failedCount) file(s) could not be transferred")
        }
        if summary.cleanupFailedCount > 0 {
            details.append("\(summary.cleanupFailedCount) copied original(s) could not be deleted")
        }
        if summary.backupFailedCount > 0 {
            details.append("\(summary.backupFailedCount) file(s) could not be backed up; originals were kept")
        }
        if let historyError {
            details.append("the import completed, but its history could not be saved: \(historyError.localizedDescription)")
        }
        if details.isEmpty == false {
            let message = details.joined(separator: "; ") + "."
            errorMessage = [errorMessage, message].compactMap { $0 }.joined(separator: " ")
        }
    }

    private func setSource(_ url: URL) {
        sourceGrant = saveGrant(url, key: DefaultsKey.sourceBookmark)
        clearScan()
        resetTransferState()
    }

    func isSelected(_ group: PhotoGroup) -> Bool {
        selectedPhotoGroupIDs.contains(group.id)
    }

    func setSelected(_ selected: Bool, for group: PhotoGroup) {
        if selected {
            selectedPhotoGroupIDs.insert(group.id)
        } else {
            selectedPhotoGroupIDs.remove(group.id)
        }
        resetTransferState()
    }

    func selectAllPhotos() {
        selectedPhotoGroupIDs = Set(photoGroups.map(\.id))
        resetTransferState()
    }

    func deselectAllPhotos() {
        selectedPhotoGroupIDs.removeAll()
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
        lastTransferRequest = nil
        ejectionState = .idle
        activeImportFolderName = nil
    }

    private func clearScan() {
        scanResult = nil
        photoGroups = []
        selectedPhotoGroupIDs = []
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
