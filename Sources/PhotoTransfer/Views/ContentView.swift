import AppKit
import Combine
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmDeletion = false

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    sourceSection
                    destinationSection
                    optionsSection
                    scanSection
                    transferSection
                }
                .padding(24)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .frame(minWidth: 650)

            if model.photoGroups.isEmpty == false {
                Divider()
                PhotoSelectionTray(model: model)
                    .frame(width: 330)
            }
        }
        .frame(minWidth: model.photoGroups.isEmpty ? 650 : 980)
        .navigationTitle("Photo Transfer")
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.refreshVolumes() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            model.refreshVolumes()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            model.refreshVolumes()
        }
        .alert("Photo Transfer", isPresented: errorIsPresented) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "An unknown error occurred.")
        }
        .confirmationDialog(
            "Transfer and delete originals?",
            isPresented: $confirmDeletion,
            titleVisibility: .visible
        ) {
            Button("Transfer, Verify, and Delete", role: .destructive) {
                Task { await model.transfer() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deletionConfirmationMessage)
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 34))
                .foregroundStyle(.blue)
                .frame(width: 54, height: 54)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text("Photo Transfer")
                    .font(.title.bold())
                Text("Copy camera files safely, then optionally clear the card.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sourceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if let url = model.sourceURL {
                    FolderPathRow(icon: "sdcard.fill", title: "Source", url: url)
                } else {
                    Label("No source selected", systemImage: "sdcard")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Menu("Detected Devices") {
                        if model.mountedVolumes.isEmpty {
                            Text("No removable volumes found")
                        } else {
                            ForEach(model.mountedVolumes) { volume in
                                Button(volume.name) { model.selectMountedVolume(volume) }
                            }
                        }
                    }
                    .menuStyle(.borderedButton)

                    Button("Choose Folder…") { model.chooseSource() }
                    Button {
                        model.refreshVolumes()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.iconOnly)
                    .help("Refresh removable volumes")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("1. Camera or SD Card", systemImage: "externaldrive.connected.to.line.below")
                .font(.headline)
        }
    }

    private var destinationSection: some View {
        GroupBox {
            VStack(spacing: 10) {
                DestinationRow(
                    label: "NEF files",
                    icon: "camera.aperture",
                    tint: .purple,
                    url: model.effectiveNEFDestinationURL,
                    choose: model.chooseNEFDestination
                )
                Divider()
                DestinationRow(
                    label: "JPEG files",
                    icon: "photo.fill",
                    tint: .orange,
                    url: model.effectiveJPEGDestinationURL,
                    choose: model.chooseJPEGDestination
                )
                Divider()
                Toggle("Create a verified backup copy", isOn: $model.backupEnabled)
                if model.backupEnabled {
                    DestinationRow(
                        label: "Backup (all files)",
                        icon: "externaldrive.badge.checkmark",
                        tint: .blue,
                        url: model.effectiveBackupDestinationURL,
                        choose: model.chooseBackupDestination
                    )
                    Label(
                        "Originals are kept unless both the primary and backup copies verify successfully.",
                        systemImage: "checkmark.shield"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Label(
                    "This import will be stored in a \(model.importFolderName) subfolder.",
                    systemImage: "calendar"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } label: {
            Label("2. Destinations", systemImage: "folder.badge.plus")
                .font(.headline)
        }
    }

    private var optionsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Other files", selection: $model.otherFilePolicy) {
                    ForEach(OtherFilePolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("Delete originals after verified transfer", isOn: $model.deleteOriginals)
                    .tint(.red)
                if model.deleteOriginals {
                    Label(
                        "Deletion is per-file and happens only after its copy is verified.",
                        systemImage: "checkmark.shield.fill"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }

                Toggle("Unmount and eject card after successful transfer", isOn: $model.ejectAfterTransfer)
                    .disabled(model.canEjectSource == false)
                if model.sourceURL != nil, model.canEjectSource == false {
                    Text("Automatic ejection is available when the source is on a mounted card or camera volume.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("3. Options", systemImage: "slider.horizontal.3")
                .font(.headline)
        }
    }

    private var scanSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        Task { await model.scan() }
                    } label: {
                        if model.isScanning {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Scan Source", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(model.canScan == false)

                    Spacer()
                    if model.scanResult != nil {
                        Text("\(model.selectedPhotoCount) selections · \(model.selectedFiles.count) files · \(byteCount(model.selectedByteCount))")
                            .foregroundStyle(.secondary)
                    }
                }

                if let result = model.scanResult {
                    HStack(spacing: 10) {
                        CountBadge(label: "NEF", count: result.nefCount, color: .purple)
                        CountBadge(label: "JPEG", count: result.jpegCount, color: .orange)
                        CountBadge(label: "Other", count: result.otherCount, color: .blue)
                        if result.skippedFileCount > 0 {
                            CountBadge(label: "Skipped", count: result.skippedFileCount, color: .gray)
                        }
                    }
                }
            }
        } label: {
            Label("4. Review", systemImage: "list.bullet.clipboard")
                .font(.headline)
        }
    }

    private var transferSection: some View {
        VStack(spacing: 12) {
            if model.isTransferring, let progress = model.transferProgress {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: Double(progress.completedCount), total: Double(max(progress.totalCount, 1)))
                    HStack {
                        Text(progress.currentFileName)
                            .lineLimit(1)
                        Spacer()
                        Text("\(progress.completedCount) of \(progress.totalCount)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if let summary = model.transferSummary {
                TransferSummaryView(summary: summary)
            }

            ejectionStatus

            Button {
                if model.deleteOriginals {
                    confirmDeletion = true
                } else {
                    Task { await model.transfer() }
                }
            } label: {
                Label(
                    transferButtonLabel,
                    systemImage: model.deleteOriginals ? "arrow.right.circle.fill" : "square.and.arrow.down.fill"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.deleteOriginals ? .red : .accentColor)
            .controlSize(.large)
            .disabled(model.canTransfer == false)
        }
    }

    @ViewBuilder
    private var ejectionStatus: some View {
        switch model.ejectionState {
        case .idle:
            EmptyView()
        case .ejecting(let name):
            HStack {
                ProgressView().controlSize(.small)
                Text("Ejecting \(name)…")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        case .ejected(let name):
            Label("\(name) was safely ejected.", systemImage: "eject.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        case .keptMounted(let message):
            Label(message, systemImage: "externaldrive.badge.exclamationmark")
                .font(.callout)
                .foregroundStyle(.orange)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if $0 == false { model.errorMessage = nil } }
        )
    }

    private var deletionConfirmationMessage: String {
        if model.backupEnabled {
            "Each original will be deleted only after both its primary and backup copies pass SHA-256 verification. Failed files stay on the source."
        } else {
            "Each original will be deleted only after its destination copy passes SHA-256 verification. Failed files stay on the source."
        }
    }

    private var transferButtonLabel: String {
        let action = model.deleteOriginals ? "Transfer, Verify, and Delete" : "Transfer"
        return if model.selectedPhotoCount == 1 {
            "\(action) 1 Selection"
        } else {
            "\(action) \(model.selectedPhotoCount) Selections"
        }
    }

    private func byteCount(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }
}

private struct FolderPathRow: View {
    let icon: String
    let title: String
    let url: URL

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(url.path(percentEncoded: false))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url.path(percentEncoded: false))
            }
        }
    }
}

private struct DestinationRow: View {
    let label: String
    let icon: String
    let tint: Color
    let url: URL?
    let choose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.medium))
                Text(url?.path(percentEncoded: false) ?? "Not selected")
                    .font(.callout)
                    .foregroundStyle(url == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Button(url == nil ? "Choose…" : "Change…", action: choose)
        }
    }
}

private struct CountBadge: View {
    let label: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(count) \(label)")
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(0.1), in: Capsule())
    }
}

private struct TransferSummaryView: View {
    let summary: TransferSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: hasIssues == false ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(hasIssues == false ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(hasIssues == false ? "Transfer complete" : "Transfer completed with issues")
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }

    private var detail: String {
        var parts = ["\(summary.copiedCount) copied"]
        if summary.alreadyPresentCount > 0 { parts.append("\(summary.alreadyPresentCount) already present") }
        if summary.deletedCount > 0 { parts.append("\(summary.deletedCount) originals deleted") }
        if summary.backupCopiedCount > 0 { parts.append("\(summary.backupCopiedCount) backed up") }
        if summary.backupFailedCount > 0 { parts.append("\(summary.backupFailedCount) backup failed") }
        if summary.cleanupFailedCount > 0 { parts.append("\(summary.cleanupFailedCount) originals kept") }
        if summary.failedCount > 0 { parts.append("\(summary.failedCount) failed") }
        return parts.joined(separator: " · ")
    }

    private var hasIssues: Bool {
        summary.failedCount > 0 || summary.backupFailedCount > 0 || summary.cleanupFailedCount > 0
    }
}
