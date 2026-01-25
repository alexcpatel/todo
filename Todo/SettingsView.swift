import SwiftUI

struct SettingsView: View {
    var body: some View {
        Form {
            Text("Data syncs automatically via iCloud")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 300)
    }
}
