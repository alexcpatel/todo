import SwiftUI

struct TaskListView: View {
    let list: TaskList
    @EnvironmentObject var store: Store

    private var incompleteTasks: [TaskItem] {
        list.items.filter { !$0.isDone }.sorted { $0.order < $1.order }
    }

    private var doneTasks: [TaskItem] {
        list.items.filter(\.isDone).sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(incompleteTasks) { task in
                    TaskRow(task: task, listID: list.id)
                }
                .onMove { store.moveTasks(in: list.id, completed: false, from: $0, to: $1) }
                .onDelete { indices in
                    for i in indices { store.deleteTask(incompleteTasks[i].id, from: list.id) }
                }

                NewTaskRow(listID: list.id)
            } header: {
                Text("Tasks").font(.subheadline.weight(.medium))
            }

            if !doneTasks.isEmpty {
                Section {
                    ForEach(doneTasks) { task in
                        TaskRow(task: task, listID: list.id)
                    }
                    .onMove { store.moveTasks(in: list.id, completed: true, from: $0, to: $1) }
                    .onDelete { indices in
                        for i in indices { store.deleteTask(doneTasks[i].id, from: list.id) }
                    }
                } header: {
                    Text("Done").font(.subheadline.weight(.medium))
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .toolbar { EditButton() }
        #else
        .listStyle(.inset)
        #endif
        .navigationTitle(list.name)
    }
}

struct NewTaskRow: View {
    let listID: UUID
    @EnvironmentObject var store: Store
    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "circle")
                .font(.title2)
                .foregroundStyle(.quaternary)

            TextField("Add a task...", text: $title)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit {
                    guard !title.isEmpty else { return }
                    store.addTask(to: listID, title: title)
                    title = ""
                    isFocused = true
                }
        }
        .padding(.vertical, 4)
    }
}

struct TaskRow: View {
    let task: TaskItem
    let listID: UUID
    @EnvironmentObject var store: Store
    @State private var editedTitle: String = ""
    @State private var isEditing = false
    @State private var showNoteEditor = false
    @FocusState private var isFocused: Bool

    private var icon: String {
        switch task.status {
        case .incomplete: return "circle"
        case .completed: return "checkmark.circle.fill"
        case .wontDo: return "minus.circle.fill"
        }
    }

    private var iconColor: Color {
        switch task.status {
        case .incomplete: return .secondary
        case .completed: return .green
        case .wontDo: return .gray
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    store.setTaskStatus(task.id, in: listID, status: task.isDone ? .incomplete : .completed)
                }
            } label: {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                if isEditing {
                    TextField("", text: $editedTitle)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit { saveAndStopEditing() }
                        .onChange(of: isFocused) { _, focused in
                            if !focused { saveAndStopEditing() }
                        }
                } else {
                    Text(task.title)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                        .onTapGesture { startEditing() }
                }

                if !task.note.isEmpty {
                    Text(task.note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if task.isDone, let date = task.completedAt {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Edit") { startEditing() }
            Button(task.note.isEmpty ? "Add Note" : "Edit Note") { showNoteEditor = true }
            Divider()
            if task.status != .completed {
                Button("Complete") { store.setTaskStatus(task.id, in: listID, status: .completed) }
            }
            if task.status != .wontDo {
                Button("Won't Do") { store.setTaskStatus(task.id, in: listID, status: .wontDo) }
            }
            if task.isDone {
                Button("Reopen") { store.setTaskStatus(task.id, in: listID, status: .incomplete) }
            }
            Divider()
            Button("Delete", role: .destructive) { store.deleteTask(task.id, from: listID) }
        }
        #if os(iOS)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { store.deleteTask(task.id, from: listID) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button { store.setTaskStatus(task.id, in: listID, status: .completed) } label: {
                Label("Complete", systemImage: "checkmark")
            }
            .tint(.green)
        }
        #endif
        #if os(iOS)
        .sheet(isPresented: $showNoteEditor) {
            NoteEditor(task: task, listID: listID)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        #else
        .popover(isPresented: $showNoteEditor) {
            NoteEditor(task: task, listID: listID)
        }
        #endif
    }

    private func startEditing() {
        editedTitle = task.title
        isEditing = true
        isFocused = true
    }

    private func saveAndStopEditing() {
        let text = editedTitle.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty, text != task.title {
            store.updateTask(task.id, in: listID, title: text, note: task.note)
        }
        isEditing = false
    }
}

struct NoteEditor: View {
    let task: TaskItem
    let listID: UUID
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var note: String
    @FocusState private var focused: Bool

    init(task: TaskItem, listID: UUID) {
        self.task = task
        self.listID = listID
        _note = State(initialValue: task.note)
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            noteEditorContent
                .navigationTitle("Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if !task.note.isEmpty {
                            Button("Clear", role: .destructive) {
                                store.updateTask(task.id, in: listID, title: task.title, note: "")
                                dismiss()
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            store.updateTask(task.id, in: listID, title: task.title, note: note)
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
        #else
        VStack(alignment: .leading, spacing: 12) {
            Text("Note").font(.headline)
            noteEditorContent
            HStack {
                if !task.note.isEmpty {
                    Button("Clear", role: .destructive) {
                        store.updateTask(task.id, in: listID, title: task.title, note: "")
                        dismiss()
                    }
                }
                Spacer()
                Button("Done") {
                    store.updateTask(task.id, in: listID, title: task.title, note: note)
                    dismiss()
                }
                .keyboardShortcut(.return)
            }
        }
        .padding()
        #endif
    }

    private var noteEditorContent: some View {
        TextEditor(text: $note)
            .font(.body)
            .frame(minWidth: 280, minHeight: 100)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .onAppear { focused = true }
    }
}
