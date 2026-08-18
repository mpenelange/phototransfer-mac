import AppKit
import QuickLookThumbnailing
import SwiftUI

struct PhotoSelectionTray: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Images")
                            .font(.headline)
                        Text("\(model.selectedPhotoCount) of \(model.photoGroups.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("All") { model.selectAllPhotos() }
                        .buttonStyle(.link)
                    Button("None") { model.deselectAllPhotos() }
                        .buttonStyle(.link)
                }

                Text("RAW+JPEG pairs appear once and always transfer together.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.photoGroups) { group in
                        PhotoSelectionRow(
                            group: group,
                            isSelected: Binding(
                                get: { model.isSelected(group) },
                                set: { model.setSelected($0, for: group) }
                            )
                        )
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .background(.background.secondary)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Image selection")
    }
}

private struct PhotoSelectionRow: View {
    let group: PhotoGroup
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            HStack(spacing: 10) {
                PhotoThumbnail(url: group.previewURL)
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.displayName)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(group.typeLabel)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.12), in: Capsule())
                        Text(group.totalByteCount.formatted(.byteCount(style: .file)))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

private struct PhotoThumbnail: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(.quaternary)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 82, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .task(id: url) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        guard let url else {
            image = nil
            return
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: CGSize(width: 164, height: 120),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        image = try? await QLThumbnailGenerator.shared
            .generateBestRepresentation(for: request)
            .nsImage
    }
}
