import SwiftUI

enum SidebarSelection: Hashable {
    case list(UUID)
    case trash
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @State private var selection: SidebarSelection?
    @Binding var showingImporter: Bool
    @Binding var showingExporter: Bool

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            switch selection {
            case .list(let id):
                if let list = store.lists.first(where: { $0.id == id }) {
                    TaskListView(list: list)
                } else {
                    Text("Select a list").foregroundStyle(.secondary)
                }
            case .trash:
                TrashView()
            case nil:
                Text("Select a list").foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showingImporter) { ImportView() }
        .sheet(isPresented: $showingExporter) { ExportView() }
    }
}

struct SidebarView: View {
    @EnvironmentObject var store: Store
    @Binding var selection: SidebarSelection?
    @State private var editingID: UUID?
    @State private var editName = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(store.activeLists) { list in
                    listRow(for: list)
                }
                .onMove { store.moveList(from: $0, to: $1) }

                Button { addNewList() } label: {
                    Label("New List", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Section {
                Label {
                    HStack {
                        Text("Trash")
                        Spacer()
                        if store.trashCount > 0 {
                            Text("\(store.trashCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } icon: {
                    Image(systemName: "trash")
                }
                .tag(SidebarSelection.trash)
            }
        }
        .navigationTitle("Lists")
        .onChange(of: isEditing) { _, focused in
            if !focused, let id = editingID {
                finishRename(id)
            }
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addNewList() } label: {
                    Image(systemName: "plus")
                }
            }
        }
        #endif
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
        .tag(SidebarSelection.list(list.id))
        .contextMenu {
            Button("Rename") { startRename(list) }
            Divider()
            Button("Delete", role: .destructive) { store.deleteList(list.id) }
        }
        #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.deleteList(list.id) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        #endif
    }

    private func addNewList() {
        let id = store.addList(name: "New List")
        selection = .list(id)
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

struct TrashView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        List {
            if store.trashedLists.isEmpty && store.trashedTasks.isEmpty {
                Text("Trash is empty")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                if !store.trashedLists.isEmpty {
                    Section("Lists") {
                        ForEach(store.trashedLists) { list in
                            TrashedListRow(list: list)
                        }
                    }
                }

                if !store.trashedTasks.isEmpty {
                    Section("Tasks") {
                        ForEach(store.trashedTasks) { task in
                            TrashedTaskRow(task: task)
                        }
                    }
                }
            }
        }
        .listStyle(.inset)
        .navigationTitle("Trash")
        .toolbar {
            if store.trashCount > 0 {
                Button("Empty Trash", role: .destructive) {
                    store.emptyTrash()
                }
            }
        }
    }
}

struct TrashedListRow: View {
    let list: TaskList
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text("\(list.items.count) tasks")
                    if let date = list.deletedAt {
                        Text("• Deleted \(date, style: .relative) ago")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Restore") { store.restoreList(list.id) }
            Divider()
            Button("Delete Permanently", role: .destructive) {
                store.permanentlyDeleteList(list.id)
            }
        }
        #if os(iOS)
        .swipeActions(edge: .leading) {
            Button { store.restoreList(list.id) } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.permanentlyDeleteList(list.id) } label: {
                Label("Delete", systemImage: "trash.slash")
            }
        }
        #endif
    }
}

struct TrashedTaskRow: View {
    let task: TaskItem
    @EnvironmentObject var store: Store

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone)

                if let date = task.deletedAt {
                    Text("Deleted \(date, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Restore") { store.restoreTask(task.id) }
            Divider()
            Button("Delete Permanently", role: .destructive) {
                store.permanentlyDeleteTask(task.id)
            }
        }
        #if os(iOS)
        .swipeActions(edge: .leading) {
            Button { store.restoreTask(task.id) } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.permanentlyDeleteTask(task.id) } label: {
                Label("Delete", systemImage: "trash.slash")
            }
        }
        #endif
    }
}
