import AppKit
import Foundation

@MainActor
enum VolumeEjector {
    static func eject(_ volume: URL) throws {
        try NSWorkspace.shared.unmountAndEjectDevice(at: volume)
    }
}
