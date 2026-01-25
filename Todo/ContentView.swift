import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var selectedListID: UUID?
    @State private var showingImporter = false

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedListID: $selectedListID)
                .toolbar {
                    ToolbarItem {
                        Button {
                            store.addList(name: "New List")
                        } label: {
                            Label("Add List", systemImage: "plus")
                        }
                    }
                    ToolbarItem {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                    }
                }
        } detail: {
            if let id = selectedListID, let list = store.lists.first(where: { $0.id == id }) {
                TaskListView(list: list)
            } else {
                Text("Select a list").foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingImporter) {
            ImportView()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var store: Store
    @Binding var selectedListID: UUID?
    @State private var editingID: UUID?

    var body: some View {
        List(selection: $selectedListID) {
            ForEach($store.lists) { $list in
                NavigationLink(value: list.id) {
                    if editingID == list.id {
                        TextField("Name", text: $list.name)
                            .onSubmit {
                                editingID = nil
                                store.save()
                            }
                    } else {
                        Text(list.name)
                            .onTapGesture(count: 2) { editingID = list.id }
                    }
                }
                .contextMenu {
                    Button("Rename") { editingID = list.id }
                    Button("Delete", role: .destructive) { store.deleteList(list) }
                }
            }
            .onMove { store.moveList(from: $0, to: $1) }
        }
        .navigationTitle("Lists")
    }
}
