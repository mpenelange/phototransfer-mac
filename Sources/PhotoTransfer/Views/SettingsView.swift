import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Toggle("Verify copied files with SHA-256", isOn: $model.verifyCopies)
                .disabled(model.deleteOriginals || model.backupEnabled)
            Text("Verification reads both files after copying. It is slower, but protects against incomplete or corrupt transfers.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if model.deleteOriginals || model.backupEnabled {
                Label("Verification cannot be disabled while deletion or backup is enabled.", systemImage: "lock.shield")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Photo Transfer Settings")
    }
}
