import Foundation

enum VolumeDiscovery {
    static func mountedExternalVolumes(fileManager: FileManager = .default) -> [MountedVolume] {
        let keys: Set<URLResourceKey> = [
            .volumeNameKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeIsReadOnlyKey
        ]
        let reportedURLs = fileManager.mountedVolumeURLs(
            includingResourceValuesForKeys: Array(keys),
            options: [.skipHiddenVolumes]
        ) ?? []
        let volumeRoot = URL(filePath: "/Volumes", directoryHint: .isDirectory)
        let cameraURLs = (try? fileManager.contentsOfDirectory(
            at: volumeRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ))?.filter { containsDCIMFolder(on: $0, fileManager: fileManager) } ?? []
        let urls = Array(Set(reportedURLs + cameraURLs))

        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: keys)
            let removable = values?.volumeIsRemovable == true
            let ejectable = values?.volumeIsEjectable == true
            let hasDCIM = containsDCIMFolder(on: url, fileManager: fileManager)
            let reportedExternal = values?.volumeIsInternal != true && (removable || ejectable)
            guard reportedExternal || hasDCIM else { return nil }
            return MountedVolume(
                url: url,
                name: (values?.volumeName ?? url.lastPathComponent)
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                isRemovable: removable,
                isEjectable: ejectable
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func preferredPhotoFolder(on volume: URL, fileManager: FileManager = .default) -> URL {
        if let dcim = dcimFolder(on: volume, fileManager: fileManager) { return dcim }
        return volume
    }

    static func containsDCIMFolder(on volume: URL, fileManager: FileManager = .default) -> Bool {
        dcimFolder(on: volume, fileManager: fileManager) != nil
    }

    static func containingVolume(for source: URL, candidates: [URL]) -> URL? {
        let sourcePath = source.standardizedFileURL.path
        if let matched = candidates
            .sorted(by: { $0.path.count > $1.path.count })
            .first(where: { candidate in
                let volumePath = candidate.standardizedFileURL.path
                return sourcePath == volumePath || sourcePath.hasPrefix(volumePath + "/")
            }) {
            return matched
        }

        let volumePrefix = "/Volumes/"
        guard sourcePath.hasPrefix(volumePrefix) else { return nil }
        let remainder = sourcePath.dropFirst(volumePrefix.count)
        guard let volumeName = remainder.split(separator: "/", maxSplits: 1).first else { return nil }
        return URL(filePath: volumePrefix, directoryHint: .isDirectory)
            .appending(path: String(volumeName), directoryHint: .isDirectory)
    }

    private static func dcimFolder(on volume: URL, fileManager: FileManager) -> URL? {
        guard let children = try? fileManager.contentsOfDirectory(
            at: volume,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        return children.first { child in
            guard child.lastPathComponent.caseInsensitiveCompare("DCIM") == .orderedSame else { return false }
            return (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }
}
