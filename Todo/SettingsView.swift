import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @State private var showingRestoreConfirm = false
    @State private var selectedBackup: Store.BackupInfo?

    var body: some View {
        Form {
            Section("Sync") {
                LabeledContent("Status", value: store.syncStatus)

                if store.isUsingiCloud {
                    Text("Data syncs automatically via iCloud Drive")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text("iCloud not available. Data stored locally.")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                Button("Refresh") {
                    store.load()
                    store.updateSyncStatus()
                    store.loadBackupsList()
                }
            }

            Section("Backups") {
                Text("Automatic backups created hourly. Last 30 backups kept.")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Button("Create Backup Now") {
                    store.createManualBackup()
                }

                if store.backups.isEmpty {
                    Text("No backups yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.backups) { backup in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(backup.date, style: .date)
                                Text(backup.date, style: .time)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Restore") {
                                selectedBackup = backup
                                showingRestoreConfirm = true
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 350, minHeight: 400)
        .alert("Restore Backup?", isPresented: $showingRestoreConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Restore", role: .destructive) {
                if let backup = selectedBackup {
                    store.restoreBackup(backup)
                }
            }
        } message: {
            Text("This will replace all current data with the backup from \(selectedBackup?.date ?? Date(), style: .date) at \(selectedBackup?.date ?? Date(), style: .time).")
        }
        .onAppear {
            store.loadBackupsList()
        }
    }
}
