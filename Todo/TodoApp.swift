import SwiftUI

@main
struct TodoApp: App {
    @StateObject private var store = Store()
    @State private var showingImporter = false
    @State private var showingRestoreAlert = false
    @State private var selectedBackup: Store.BackupInfo?

    var body: some Scene {
        #if os(macOS)
        Window("Todo", id: "main") {
            ContentView(showingImporter: $showingImporter)
                .environmentObject(store)
                .alert("Restore Backup?", isPresented: $showingRestoreAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Restore", role: .destructive) {
                        if let backup = selectedBackup {
                            store.restoreBackup(backup)
                        }
                    }
                } message: {
                    if let backup = selectedBackup {
                        Text("Replace all data with backup from \(backup.date.formatted(date: .abbreviated, time: .shortened))?")
                    }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}

            CommandGroup(after: .importExport) {
                Button("Import from TickTick...") { showingImporter = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])

                Divider()

                Button("Create Backup Now") {
                    store.createManualBackup()
                }
                .keyboardShortcut("b", modifiers: [.command, .shift])

                Menu("Restore from Backup") {
                    if store.backups.isEmpty {
                        Text("No backups available")
                    } else {
                        ForEach(store.backups) { backup in
                            Button(backup.date.formatted(date: .abbreviated, time: .shortened)) {
                                selectedBackup = backup
                                showingRestoreAlert = true
                            }
                        }
                    }
                }
            }
        }
        Settings {
            SettingsView()
                .environmentObject(store)
        }
        #else
        WindowGroup {
            ContentView(showingImporter: $showingImporter)
                .environmentObject(store)
        }
        #endif
    }
}
