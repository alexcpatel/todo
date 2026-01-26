import SwiftUI

enum SidebarSelection: Hashable {
    case list(UUID)
    case trash
    case settings
}

struct ContentView: View {
    @EnvironmentObject var store: Store
    @Binding var showingImporter: Bool

    var body: some View {
        #if os(iOS)
        NavigationStack {
            SidebarListView()
        }
        #else
        MacContentView()
            .sheet(isPresented: $showingImporter) { ImportView() }
        #endif
    }
}

#if os(iOS)
struct SidebarListView: View {
    @EnvironmentObject var store: Store
    @State private var editingID: UUID?
    @State private var editName = ""
    @State private var scrollTarget: UUID?
    @FocusState private var isEditing: Bool

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(store.activeLists) { list in
                        NavigationLink(value: SidebarSelection.list(list.id)) {
                            listRowContent(for: list)
                        }
                        .id(list.id)
                        .contextMenu {
                            Button("Rename") { startRename(list) }
                            Divider()
                            Button("Delete", role: .destructive) { store.deleteList(list.id) }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { store.deleteList(list.id) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove { store.moveList(from: $0, to: $1) }

                    Button { addNewList() } label: {
                        Label("New List", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }

                Section {
                    NavigationLink(value: SidebarSelection.trash) {
                        HStack(spacing: 6) {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text("Trash")
                            Spacer()
                            if store.trashCount > 0 {
                                Text("\(store.trashCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    NavigationLink(value: SidebarSelection.settings) {
                        HStack(spacing: 6) {
                            Image(systemName: "gear")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Text("Settings")
                        }
                    }
                }
            }
            .onChange(of: scrollTarget) { _, target in
                if let target {
                    withAnimation {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    scrollTarget = nil
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
        .navigationTitle("Lists")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: SidebarSelection.self) { selection in
            switch selection {
            case .list(let id):
                if let list = store.lists.first(where: { $0.id == id }) {
                    TaskListView(list: list)
                }
            case .trash:
                TrashView()
            case .settings:
                SettingsView()
                    .navigationTitle("Settings")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addNewList() } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isEditing = false }
            }
        }
        .onChange(of: isEditing) { _, focused in
            if !focused, let id = editingID {
                finishRename(id)
            }
        }
    }

    @ViewBuilder
    private func listRowContent(for list: TaskList) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet")
                .foregroundStyle(.secondary)
                .frame(width: 20)

            if editingID == list.id {
                TextField("", text: $editName)
                    .textFieldStyle(.plain)
                    .focused($isEditing)
                    .submitLabel(.done)
                    .onSubmit { finishRename(list.id) }
            } else {
                Text(list.name)
                    .foregroundStyle(.primary)
            }
        }
    }

    private func addNewList() {
        let id = store.addList(name: "New List")
        scrollTarget = id
        if let list = store.lists.first(where: { $0.id == id }) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
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
#endif

#if os(macOS)
struct MacContentView: View {
    @EnvironmentObject var store: Store
    @State private var selection: SidebarSelection?
    @State private var editingID: UUID?
    @State private var editName = ""
    @FocusState private var isEditing: Bool

    var body: some View {
        NavigationSplitView {
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
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Trash")
                        Spacer()
                        if store.trashCount > 0 {
                            Text("\(store.trashCount)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
        } detail: {
            switch selection {
            case .list(let id):
                if let list = store.lists.first(where: { $0.id == id }) {
                    TaskListView(list: list)
                } else {
                    ContentUnavailableView("Select a List", systemImage: "list.bullet", description: Text("Choose a list from the sidebar"))
                }
            case .trash:
                TrashView()
            case .settings:
                SettingsView()
            case nil:
                ContentUnavailableView("Select a List", systemImage: "list.bullet", description: Text("Choose a list from the sidebar"))
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
        .tag(SidebarSelection.list(list.id))
        .contextMenu {
            Button("Rename") { startRename(list) }
            Divider()
            Button("Delete", role: .destructive) { deleteList(list) }
        }
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

    private func deleteList(_ list: TaskList) {
        if selection == .list(list.id) {
            selection = nil
        }
        store.deleteList(list.id)
    }
}
#endif

struct TrashView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Group {
            if store.trashedLists.isEmpty && store.trashedTasks.isEmpty {
                ContentUnavailableView("Trash is Empty", systemImage: "trash", description: Text("Deleted items will appear here"))
            } else {
                List {
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
                #if os(iOS)
                .listStyle(.insetGrouped)
                #else
                .listStyle(.inset)
                #endif
                .animation(.smooth(duration: 0.3), value: store.trashedLists.map(\.id))
                .animation(.smooth(duration: 0.3), value: store.trashedTasks.map(\.id))
            }
        }
        .navigationTitle("Trash")
        .toolbar {
            if store.trashCount > 0 {
                Button("Empty Trash", role: .destructive) {
                    withAnimation { store.emptyTrash() }
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
            Button("Restore") { withAnimation { store.restoreList(list.id) } }
            Divider()
            Button("Delete Permanently", role: .destructive) {
                withAnimation { store.permanentlyDeleteList(list.id) }
            }
        }
        #if os(iOS)
        .swipeActions(edge: .leading) {
            Button { withAnimation { store.restoreList(list.id) } } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            .tint(.blue)
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { withAnimation { store.permanentlyDeleteList(list.id) } } label: {
                Label("Delete", systemImage: "trash.slash")
            }
        }
        #endif
    }
}

struct TrashedTaskRow: View {
    let task: TaskItem
    @EnvironmentObject var store: Store

    private var canRestore: Bool { store.canRestoreTask(task.id) }
    private var listName: String? { store.listName(for: task.originalListID) }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone)

                HStack(spacing: 4) {
                    if let name = listName {
                        Text(name)
                        if !canRestore {
                            Text("(deleted)")
                        }
                    }
                    if let date = task.deletedAt {
                        if listName != nil { Text("•") }
                        Text("Deleted \(date, style: .relative) ago")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contextMenu {
            if canRestore {
                Button("Restore") { withAnimation { store.restoreTask(task.id) } }
                Divider()
            }
            Button("Delete Permanently", role: .destructive) {
                withAnimation { store.permanentlyDeleteTask(task.id) }
            }
        }
        #if os(iOS)
        .swipeActions(edge: .leading) {
            if canRestore {
                Button { withAnimation { store.restoreTask(task.id) } } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { withAnimation { store.permanentlyDeleteTask(task.id) } } label: {
                Label("Delete", systemImage: "trash.slash")
            }
        }
        #endif
    }
}
