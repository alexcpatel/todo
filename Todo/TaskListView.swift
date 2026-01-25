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
        .listStyle(.inset)
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
    @State private var isEditingTitle = false
    @State private var editTitle = ""
    @State private var showNoteEditor = false
    @FocusState private var titleFocused: Bool

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
                if isEditingTitle {
                    TextField("", text: $editTitle)
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                        .onSubmit { saveTitle() }
                        .onChange(of: titleFocused) { _, focused in
                            if !focused { saveTitle() }
                        }
                } else {
                    Text(task.title)
                        .strikethrough(task.isDone)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                }

                if !task.note.isEmpty {
                    Text(task.note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { startEditingTitle() }

            if task.isDone, let date = task.completedAt {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Edit Title") { startEditingTitle() }
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
        .popover(isPresented: $showNoteEditor) {
            NoteEditor(task: task, listID: listID)
        }
    }

    private func startEditingTitle() {
        editTitle = task.title
        isEditingTitle = true
        titleFocused = true
    }

    private func saveTitle() {
        let text = editTitle.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty, text != task.title {
            store.updateTask(task.id, in: listID, title: text, note: task.note)
        }
        isEditingTitle = false
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
        VStack(alignment: .leading, spacing: 12) {
            Text("Note").font(.headline)

            TextEditor(text: $note)
                .font(.body)
                .frame(minWidth: 280, minHeight: 100)
                .scrollContentBackground(.hidden)
                .focused($focused)

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
        .onAppear { focused = true }
    }
}
