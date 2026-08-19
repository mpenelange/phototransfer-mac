import AppKit
import Combine
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmDeletion = false

    var body: some View {
        HStack(spacing: 0) {
            operationsSidebar

            Divider()

            workspace
                .frame(minWidth: 560)

            if model.photoGroups.isEmpty == false {
                Divider()
                PhotoSelectionTray(model: model)
                    .frame(width: 340)
            }
        }
        .frame(minWidth: model.photoGroups.isEmpty ? 900 : 1_220, minHeight: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .navigationTitle("Photo Transfer")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    model.refreshVolumes()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh removable volumes")

                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Scan", systemImage: "magnifyingglass")
                }
                .disabled(model.canScan == false)

                Button {
                    startTransfer()
                } label: {
                    Label("Transfer", systemImage: model.deleteOriginals ? "arrow.right.circle.fill" : "square.and.arrow.down.fill")
                }
                .disabled(model.canTransfer == false)
            }
        }
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

    private var operationsSidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            sidebarHeader

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Source", systemImage: "externaldrive.connected.to.line.below")

                if let url = model.sourceURL {
                    CompactPathRow(icon: "sdcard.fill", title: "Camera Card", url: url)
                } else {
                    CompactPlaceholderRow(icon: "sdcard", title: "No source selected")
                }

                HStack(spacing: 8) {
                    Menu {
                        if model.mountedVolumes.isEmpty {
                            Text("No removable volumes found")
                        } else {
                            ForEach(model.mountedVolumes) { volume in
                                Button(volume.name) { model.selectMountedVolume(volume) }
                            }
                        }
                    } label: {
                        Label("Devices", systemImage: "externaldrive")
                    }
                    .menuStyle(.borderedButton)

                    Button("Choose", action: model.chooseSource)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Destinations", systemImage: "folder.badge.plus")

                DestinationRow(
                    label: "NEF",
                    icon: "camera.aperture",
                    tint: .purple,
                    url: model.effectiveNEFDestinationURL,
                    choose: model.chooseNEFDestination
                )
                DestinationRow(
                    label: "JPEG",
                    icon: "photo.fill",
                    tint: .orange,
                    url: model.effectiveJPEGDestinationURL,
                    choose: model.chooseJPEGDestination
                )

                Toggle("Backup", isOn: $model.backupEnabled)
                if model.backupEnabled {
                    DestinationRow(
                        label: "Backup",
                        icon: "externaldrive.badge.checkmark",
                        tint: .blue,
                        url: model.effectiveBackupDestinationURL,
                        choose: model.chooseBackupDestination
                    )
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel("Import Rules", systemImage: "slider.horizontal.3")

                Picker("Other", selection: $model.otherFilePolicy) {
                    ForEach(OtherFilePolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Delete originals", isOn: $model.deleteOriginals)
                    .tint(.red)

                Toggle("Eject on success", isOn: $model.ejectAfterTransfer)
                    .disabled(model.canEjectSource == false)
            }

            Spacer()

            ImportFolderStrip(folderName: model.importFolderName)
        }
        .padding(18)
        .frame(width: 300)
        .background(.regularMaterial)
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)
                .background(.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 1) {
                Text("Photo Transfer")
                    .font(.headline)
                Text("Import")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            workspaceHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let result = model.scanResult {
                        scanOverview(result)
                    } else {
                        emptyReview
                    }

                    transferPanel
                    ejectionStatus
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private var workspaceHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(workspaceTitle)
                    .font(.title3.weight(.semibold))
                Text(workspaceSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if model.isScanning {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await model.scan() }
            } label: {
                Label("Scan Source", systemImage: "magnifyingglass")
            }
            .disabled(model.canScan == false)

            Button {
                startTransfer()
            } label: {
                Label(transferButtonLabel, systemImage: model.deleteOriginals ? "arrow.right.circle.fill" : "square.and.arrow.down.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(model.deleteOriginals ? .red : .accentColor)
            .disabled(model.canTransfer == false)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var emptyReview: some View {
        ProPanel {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "rectangle.stack.badge.plus")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("No import scanned")
                        .font(.headline)
                    Text("Select a source, then scan to review camera files.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
        }
    }

    private func scanOverview(_ result: ScanResult) -> some View {
        ProPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Review")
                        .font(.headline)
                    Spacer()
                    Text("\(model.selectedPhotoCount) of \(model.photoGroups.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 10) {
                    StatTile(label: "NEF", value: "\(result.nefCount)", color: .purple)
                    StatTile(label: "JPEG", value: "\(result.jpegCount)", color: .orange)
                    StatTile(label: "Other", value: "\(result.otherCount)", color: .blue)
                    StatTile(label: "Files", value: "\(model.selectedFiles.count)", color: .gray)
                }

                VStack(spacing: 0) {
                    SummaryRow(label: "Selected data", value: byteCount(model.selectedByteCount))
                    Divider()
                    SummaryRow(label: "Import folder", value: model.importFolderName)
                    if result.skippedFileCount > 0 {
                        Divider()
                        SummaryRow(label: "Skipped", value: "\(result.skippedFileCount) files")
                    }
                }
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private var transferPanel: some View {
        ProPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Transfer")
                        .font(.headline)
                    Spacer()
                    Text(model.canTransfer ? "Ready" : "Waiting")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(model.canTransfer ? .green : .secondary)
                }

                if model.isTransferring, let progress = model.transferProgress {
                    VStack(alignment: .leading, spacing: 7) {
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

                HStack(spacing: 10) {
                    CapabilityBadge(label: model.verifyCopies ? "SHA-256" : "No verify", systemImage: "checkmark.shield")
                    CapabilityBadge(label: model.backupEnabled ? "Backup" : "Primary only", systemImage: "externaldrive")
                    CapabilityBadge(label: model.deleteOriginals ? "Delete" : "Keep originals", systemImage: model.deleteOriginals ? "trash" : "lock")
                }
            }
        }
    }

    @ViewBuilder
    private var ejectionStatus: some View {
        switch model.ejectionState {
        case .idle:
            EmptyView()
        case .ejecting(let name):
            StatusStrip(systemImage: "eject", message: "Ejecting \(name)...", color: .secondary, showsProgress: true)
        case .ejected(let name):
            StatusStrip(systemImage: "eject.circle.fill", message: "\(name) was safely ejected.", color: .green)
        case .keptMounted(let message):
            StatusStrip(systemImage: "externaldrive.badge.exclamationmark", message: message, color: .orange)
        case .failed(let message):
            StatusStrip(systemImage: "exclamationmark.triangle.fill", message: message, color: .orange)
        }
    }

    private var workspaceTitle: String {
        if model.isTransferring { return "Transferring" }
        if model.scanResult != nil { return "Import Review" }
        return "Import Workspace"
    }

    private var workspaceSubtitle: String {
        if model.scanResult != nil {
            return "\(model.selectedPhotoCount) selections / \(model.selectedFiles.count) files / \(byteCount(model.selectedByteCount))"
        }
        return model.sourceURL?.lastPathComponent ?? "No source selected"
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
        model.deleteOriginals ? "Transfer and Delete" : "Transfer"
    }

    private func startTransfer() {
        if model.deleteOriginals {
            confirmDeletion = true
        } else {
            Task { await model.transfer() }
        }
    }

    private func byteCount(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }
}

private struct SectionLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }
}

private struct ProPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(14)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .stroke(.separator.opacity(0.45), lineWidth: 1)
            }
    }
}

private struct CompactPathRow: View {
    let icon: String
    let title: String
    let url: URL

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(url.path(percentEncoded: false))
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(url.path(percentEncoded: false))
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct CompactPlaceholderRow: View {
    let icon: String
    let title: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct DestinationRow: View {
    let label: String
    let icon: String
    let tint: Color
    let url: URL?
    let choose: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                Text(url?.path(percentEncoded: false) ?? "Not selected")
                    .font(.caption)
                    .foregroundStyle(url == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            Button(url == nil ? "Set" : "Edit", action: choose)
                .controlSize(.small)
        }
        .padding(9)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct ImportFolderStrip: View {
    let folderName: String

    var body: some View {
        HStack {
            Label(folderName, systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct StatTile: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.semibold))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(color)
                .frame(width: 3)
                .clipShape(RoundedRectangle(cornerRadius: 2))
        }
    }
}

private struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct CapabilityBadge: View {
    let label: String
    let systemImage: String

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct StatusStrip: View {
    let systemImage: String
    let message: String
    let color: Color
    var showsProgress = false

    var body: some View {
        HStack(spacing: 9) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
            }
            Text(message)
                .font(.callout)
                .foregroundStyle(color)
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}

private struct TransferSummaryView: View {
    let summary: TransferSummary

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: hasIssues == false ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(hasIssues == false ? .green : .orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(hasIssues == false ? "Transfer complete" : "Transfer completed with issues")
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
    }

    private var detail: String {
        var parts = ["\(summary.copiedCount) copied"]
        if summary.alreadyPresentCount > 0 { parts.append("\(summary.alreadyPresentCount) already present") }
        if summary.deletedCount > 0 { parts.append("\(summary.deletedCount) originals deleted") }
        if summary.backupCopiedCount > 0 { parts.append("\(summary.backupCopiedCount) backed up") }
        if summary.backupFailedCount > 0 { parts.append("\(summary.backupFailedCount) backup failed") }
        if summary.cleanupFailedCount > 0 { parts.append("\(summary.cleanupFailedCount) originals kept") }
        if summary.failedCount > 0 { parts.append("\(summary.failedCount) failed") }
        return parts.joined(separator: " / ")
    }

    private var hasIssues: Bool {
        summary.failedCount > 0 || summary.backupFailedCount > 0 || summary.cleanupFailedCount > 0
    }
}
