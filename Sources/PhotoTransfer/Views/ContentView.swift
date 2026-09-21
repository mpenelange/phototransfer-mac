import AppKit
import Combine
import SwiftUI

struct ContentView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var confirmDeletion = false
    @State private var inspectorPresented = true

    var body: some View {
        HStack(spacing: 0) {
            sourceNavigator
                .frame(width: 300)

            Divider()

            workspace
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if inspectorPresented {
                Divider()

                importInspector
                    .frame(width: 340)
            }
        }
        .frame(minWidth: 1_320, minHeight: 720)
        .navigationTitle(workspaceNavigationTitle)
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
            }

            ToolbarItem {
                Button {
                    inspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Show or hide import settings")
            }

            ToolbarItem(placement: .primaryAction) {
                transferToolbarButton
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

    private var sourceNavigator: some View {
        List {
            Section("Source") {
                if let url = model.sourceURL {
                    SourceListRow(
                        title: url.lastPathComponent,
                        subtitle: url.path(percentEncoded: false),
                        systemImage: "sdcard.fill"
                    )

                    Button {
                        model.chooseSource()
                    } label: {
                        Label("Change Source", systemImage: "folder")
                    }
                } else {
                    SourceListRow(
                        title: "No Source",
                        subtitle: "Choose a card, camera volume, or folder",
                        systemImage: "sdcard"
                    )

                    Button {
                        model.chooseSource()
                    } label: {
                        Label("Choose Folder", systemImage: "folder")
                    }

                    Menu {
                        if model.mountedVolumes.isEmpty {
                            Text("No removable volumes found")
                        } else {
                            ForEach(model.mountedVolumes) { volume in
                                Button(volume.name) { model.selectMountedVolume(volume) }
                            }
                        }
                    } label: {
                        Label("Detected Devices", systemImage: "externaldrive")
                    }
                }
            }

            if model.mountedVolumes.isEmpty == false {
                Section("Mounted") {
                    ForEach(model.mountedVolumes) { volume in
                        Button {
                            model.selectMountedVolume(volume)
                        } label: {
                            SourceListRow(
                                title: volume.name,
                                subtitle: volume.url.path(percentEncoded: false),
                                systemImage: volume.isEjectable ? "externaldrive.badge.checkmark" : "externaldrive"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .controlSize(.small)
    }

    private var workspace: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)
                .opacity(0.18)
                .ignoresSafeArea()

            if model.photoGroups.isEmpty {
                emptyWorkspace
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -36)
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            if let result = model.scanResult {
                                scanOverview(result)
                            }

                            transferPanel
                            ejectionStatus
                        }
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    Divider()

                    PhotoSelectionTray(model: model)
                        .frame(width: 380)
                }
            }
        }
    }

    private var emptyWorkspace: some View {
        VStack(spacing: 18) {
            Image(systemName: readinessIcon)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(spacing: 5) {
                Text(readinessTitle)
                    .font(.title3.weight(.semibold))
                Text(readinessSubtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack {
                Button {
                    readinessPrimaryAction()
                } label: {
                    Label(readinessActionLabel, systemImage: readinessActionIcon)
                }
                .buttonStyle(.borderedProminent)
                .disabled(readinessActionIsDisabled)

                if model.sourceURL == nil {
                    Menu {
                        if model.mountedVolumes.isEmpty {
                            Text("No removable volumes found")
                        } else {
                            ForEach(model.mountedVolumes) { volume in
                                Button(volume.name) { model.selectMountedVolume(volume) }
                            }
                        }
                    } label: {
                        Label("Detected Devices", systemImage: "externaldrive")
                    }
                    .menuStyle(.borderedButton)
                }
            }
        }
        .padding(32)
    }

    private var importInspector: some View {
        Form {
            Section("Destinations") {
                InspectorDestinationRow(
                    label: "NEF",
                    systemImage: "camera.aperture",
                    tint: .purple,
                    url: model.effectiveNEFDestinationURL,
                    choose: model.chooseNEFDestination
                )

                InspectorDestinationRow(
                    label: "JPEG",
                    systemImage: "photo",
                    tint: .orange,
                    url: model.effectiveJPEGDestinationURL,
                    choose: model.chooseJPEGDestination
                )

                Toggle("Backup", isOn: $model.backupEnabled)

                if model.backupEnabled {
                    InspectorDestinationRow(
                        label: "Backup",
                        systemImage: "externaldrive.badge.checkmark",
                        tint: .secondary,
                        url: model.effectiveBackupDestinationURL,
                        choose: model.chooseBackupDestination
                    )
                }
            }

            Section("Naming") {
                LabeledContent("Import folder", value: model.importFolderName)
            }

            Section("Rules") {
                Picker("Other files", selection: $model.otherFilePolicy) {
                    ForEach(OtherFilePolicy.allCases) { policy in
                        Text(policy.label).tag(policy)
                    }
                }

                Toggle("New files only", isOn: $model.newFilesOnly)

                Toggle("Delete originals", isOn: $model.deleteOriginals)
                    .tint(.red)

                Toggle("Eject on success", isOn: $model.ejectAfterTransfer)
                    .disabled(model.canEjectSource == false)
            }
        }
        .formStyle(.grouped)
        .controlSize(.small)
    }

    @ViewBuilder
    private var transferToolbarButton: some View {
        if model.canTransfer {
            Button {
                startTransfer()
            } label: {
                Label(transferButtonLabel, systemImage: model.deleteOriginals ? "arrow.right.circle.fill" : "square.and.arrow.down.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(model.deleteOriginals ? .red : .accentColor)
        } else {
            Button {
                startTransfer()
            } label: {
                Label(transferButtonLabel, systemImage: model.deleteOriginals ? "arrow.right.circle.fill" : "square.and.arrow.down.fill")
            }
            .buttonStyle(.bordered)
            .disabled(true)
        }
    }

    private func scanOverview(_ result: ScanResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Review")
                        .font(.headline)
                    Text("\(model.selectedPhotoCount) of \(model.photoGroups.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var transferPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                if model.canRetryFailed {
                    Button("Retry \(model.failedTransferCount) Failed") {
                        Task { await model.retryFailedTransfer() }
                    }
                }
            }

            HStack(spacing: 10) {
                CapabilityBadge(label: model.verifyCopies ? "Verified" : "Unverified", systemImage: "checkmark.shield")
                CapabilityBadge(label: model.backupEnabled ? "Backup" : "Primary only", systemImage: "externaldrive")
                CapabilityBadge(label: model.deleteOriginals ? "Delete" : "Keep originals", systemImage: model.deleteOriginals ? "trash" : "lock")
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
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

    private var readinessTitle: String {
        if model.sourceURL == nil { return "Choose a source to import photos" }
        if model.nefDestinationURL == nil || model.jpegDestinationURL == nil { return "Set import destinations" }
        if model.backupEnabled, model.backupDestinationURL == nil { return "Set backup destination" }
        return "Ready to scan"
    }

    private var workspaceNavigationTitle: String {
        if model.isTransferring { return "Transferring" }
        if model.scanResult != nil { return "Review Import" }
        return "Import"
    }

    private var readinessSubtitle: String {
        if model.sourceURL == nil { return "Start with a mounted card, camera volume, or DCIM folder." }
        if model.nefDestinationURL == nil || model.jpegDestinationURL == nil { return "Choose where RAW and JPEG files should land." }
        if model.backupEnabled, model.backupDestinationURL == nil { return "Backup is enabled, so choose a backup destination before scanning." }
        return "Scan the source to review photos before transfer."
    }

    private var readinessIcon: String {
        if model.sourceURL == nil { return "sdcard" }
        if model.canScan { return "photo.on.rectangle.angled" }
        return "folder.badge.plus"
    }

    private var readinessActionLabel: String {
        if model.sourceURL == nil { return "Choose Source" }
        if model.nefDestinationURL == nil { return "Set NEF Destination" }
        if model.jpegDestinationURL == nil { return "Set JPEG Destination" }
        if model.backupEnabled, model.backupDestinationURL == nil { return "Set Backup Destination" }
        return "Scan Source"
    }

    private var readinessActionIcon: String {
        if model.canScan { return "magnifyingglass" }
        return "folder"
    }

    private var readinessActionIsDisabled: Bool {
        readinessActionLabel == "Scan Source" && model.canScan == false
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if $0 == false { model.errorMessage = nil } }
        )
    }

    private var deletionConfirmationMessage: String {
        if model.backupEnabled {
            "Each original will be deleted only after both its primary and backup copies pass verification. Failed files stay on the source."
        } else {
            "Each original will be deleted only after its destination copy passes verification. Failed files stay on the source."
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

    private func readinessPrimaryAction() {
        if model.sourceURL == nil {
            model.chooseSource()
        } else if model.nefDestinationURL == nil {
            model.chooseNEFDestination()
        } else if model.jpegDestinationURL == nil {
            model.chooseJPEGDestination()
        } else if model.backupEnabled, model.backupDestinationURL == nil {
            model.chooseBackupDestination()
        } else {
            Task { await model.scan() }
        }
    }

    private func byteCount(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }
}

private struct SourceListRow: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
        }
        .help(subtitle)
    }
}

private struct InspectorDestinationRow: View {
    let label: String
    let systemImage: String
    let tint: Color
    let url: URL?
    let choose: () -> Void

    var body: some View {
        LabeledContent {
            Button(url == nil ? "Set" : "Edit", action: choose)
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                    Text(url?.path(percentEncoded: false) ?? "Not selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)
            }
        }
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
