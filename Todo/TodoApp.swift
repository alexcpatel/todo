import SwiftUI

@main
struct TodoApp: App {
    @StateObject private var store = Store()
    @State private var showingImporter = false
    @State private var showingExporter = false

    var body: some Scene {
        Window("Todo", id: "main") {
            ContentView(showingImporter: $showingImporter, showingExporter: $showingExporter)
                .environmentObject(store)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            #if os(macOS)
            CommandGroup(replacing: .saveItem) {}
            #endif

            CommandGroup(after: .importExport) {
                Button("Import from TickTick...") { showingImporter = true }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Export to TickTick...") { showingExporter = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(store)
        }
        #endif
    }
}
