import Foundation

enum MediaKind: String, CaseIterable, Sendable {
    case nef
    case jpeg
    case other

    var label: String {
        switch self {
        case .nef: "NEF"
        case .jpeg: "JPEG"
        case .other: "Other"
        }
    }

    static func classify(_ url: URL) -> MediaKind {
        switch url.pathExtension.lowercased() {
        case "nef": .nef
        case "jpg", "jpeg": .jpeg
        default: .other
        }
    }
}

enum OtherFilePolicy: String, CaseIterable, Identifiable, Sendable {
    case jpegDestination
    case nefDestination
    case skip

    var id: Self { self }

    var label: String {
        switch self {
        case .jpegDestination: "JPEG destination"
        case .nefDestination: "NEF destination"
        case .skip: "Skip other files"
        }
    }
}

struct SourceFile: Identifiable, Hashable, Sendable {
    let url: URL
    let kind: MediaKind
    let byteCount: Int64

    var id: URL { url }
}

struct ScanResult: Sendable {
    let files: [SourceFile]
    let skippedFileCount: Int

    var nefCount: Int { files.count(where: { $0.kind == .nef }) }
    var jpegCount: Int { files.count(where: { $0.kind == .jpeg }) }
    var otherCount: Int { files.count(where: { $0.kind == .other }) }
    var totalByteCount: Int64 { files.reduce(0) { $0 + $1.byteCount } }

    static let empty = ScanResult(files: [], skippedFileCount: 0)
}

struct TransferRequest: Sendable {
    let sourceRoot: URL
    let files: [SourceFile]
    let nefDestination: URL
    let jpegDestination: URL
    let backupDestination: URL?
    let importFolderName: String
    let otherFilePolicy: OtherFilePolicy
    let deleteOriginals: Bool
    let verifyCopies: Bool
}

enum ImportFolderNaming {
    static func folderName(for date: Date = .now, timeZone: TimeZone = .current) -> String {
        date.formatted(
            Date.ISO8601FormatStyle(timeZone: timeZone)
                .year()
                .month()
                .day()
                .dateSeparator(.dash)
        )
    }
}

enum TransferOutcome: Sendable {
    case copied
    case alreadyPresent
    case skipped
    case backupFailed(String, primaryAlreadyPresent: Bool)
    case cleanupFailed(String, alreadyPresent: Bool)
    case failed(String)
}

struct TransferItemResult: Sendable {
    let source: URL
    let destination: URL?
    let backupDestination: URL?
    let outcome: TransferOutcome
    let originalDeleted: Bool
}

struct TransferProgress: Sendable {
    let completedCount: Int
    let totalCount: Int
    let currentFileName: String
    let copiedByteCount: Int64
    let totalByteCount: Int64
}

struct TransferSummary: Sendable {
    let results: [TransferItemResult]
    let copiedByteCount: Int64

    var copiedCount: Int {
        results.count(where: {
            switch $0.outcome {
            case .copied,
                 .backupFailed(_, primaryAlreadyPresent: false),
                 .cleanupFailed(_, alreadyPresent: false): true
            default: false
            }
        })
    }
    var alreadyPresentCount: Int {
        results.count(where: {
            switch $0.outcome {
            case .alreadyPresent,
                 .backupFailed(_, primaryAlreadyPresent: true),
                 .cleanupFailed(_, alreadyPresent: true): true
            default: false
            }
        })
    }
    var backupCopiedCount: Int { results.count(where: { $0.backupDestination != nil }) }
    var backupFailedCount: Int {
        results.count(where: { if case .backupFailed = $0.outcome { true } else { false } })
    }
    var skippedCount: Int { results.count(where: { if case .skipped = $0.outcome { true } else { false } }) }
    var failedCount: Int { results.count(where: { if case .failed = $0.outcome { true } else { false } }) }
    var cleanupFailedCount: Int { results.count(where: { if case .cleanupFailed = $0.outcome { true } else { false } }) }
    var deletedCount: Int { results.count(where: \.originalDeleted) }
    var isFullySuccessful: Bool {
        failedCount == 0 && backupFailedCount == 0 && cleanupFailedCount == 0
    }
    var failures: [TransferItemResult] {
        results.filter {
            switch $0.outcome {
            case .failed, .backupFailed, .cleanupFailed: true
            default: false
            }
        }
    }
}

enum EjectionState: Equatable, Sendable {
    case idle
    case ejecting(String)
    case ejected(String)
    case keptMounted(String)
    case failed(String)
}

struct MountedVolume: Identifiable, Hashable, Sendable {
    let url: URL
    let name: String
    let isRemovable: Bool
    let isEjectable: Bool

    var id: URL { url }
}
