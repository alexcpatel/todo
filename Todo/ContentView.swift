import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var selectedListID: UUID?
    @Binding var showingImporter: Bool
    @Binding var showingExporter: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedListID: $selectedListID)
        } detail: {
            if let id = selectedListID, let list = store.lists.first(where: { $0.id == id }) {
                TaskListView(list: list)
            } else {
                Text("Select a list").foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingImporter) { ImportView() }
        .sheet(isPresented: $showingExporter) { ExportView() }
    }
}

struct SidebarView: View {
    @EnvironmentObject var store: Store
    @Binding var selectedListID: UUID?
    @State private var editingID: UUID?
    @State private var editName = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        List(selection: $selectedListID) {
            ForEach(store.lists) { list in
                listRow(for: list)
            }
            .onMove { store.moveList(from: $0, to: $1) }

            Button { addNewList() } label: {
                Label("New List", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Lists")
        .onChange(of: isEditing) { _, focused in
            if !focused, let id = editingID {
                finishRename(id)
            }
        }
    }

    @ViewBuilder
    private func listRow(for list: TaskList) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            if editingID == list.id {
                TextField("", text: $editName)
                    .textFieldStyle(.plain)
                    .focused($isEditing)
                    .onSubmit { finishRename(list.id) }
            } else {
                Text(list.name)
            }
        }
        .tag(list.id)
        .contextMenu {
            Button("Rename") { startRename(list) }
            Divider()
            Button("Delete", role: .destructive) { store.deleteList(list.id) }
        }
    }

    private func addNewList() {
        let id = store.addList(name: "New List")
        selectedListID = id
        if let list = store.lists.first(where: { $0.id == id }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                startRename(list)
            }
        }
    }

    private func startRename(_ list: TaskList) {
        editName = list.name
        editingID = list.id
        isEditing = true
    }

    private func finishRename(_ id: UUID) {
        let name = editName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            store.renameList(id, to: name)
        }
        editingID = nil
    }
}
