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
        #if os(iOS)
        .toolbar { EditButton() }
        #endif
    }
}

struct NewTaskRow: View {
    let listID: UUID
    @EnvironmentObject var store: Store
    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "circle")
                .font(.title2)
                .foregroundStyle(.tertiary)

            TextField("Add a task...", text: $title)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(addTask)
        }
        .padding(.vertical, 4)
    }

    private func addTask() {
        guard !title.isEmpty else { return }
        store.addTask(to: listID, title: title)
        title = ""
        isFocused = true
    }
}

struct TaskRow: View {
    let task: TaskItem
    let listID: UUID
    @EnvironmentObject var store: Store
    @State private var isEditing = false

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
                withAnimation {
                    let newStatus: TaskStatus = task.isDone ? .incomplete : .completed
                    store.setTaskStatus(task.id, in: listID, status: newStatus)
                }
            } label: {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)

                if !task.note.isEmpty {
                    Text(task.note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if task.isDone, let date = task.completedAt {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Edit") { isEditing = true }
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
        .sheet(isPresented: $isEditing) {
            TaskEditSheet(task: task, listID: listID)
        }
    }
}

struct TaskEditSheet: View {
    let task: TaskItem
    let listID: UUID
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var note: String

    init(task: TaskItem, listID: UUID) {
        self.task = task
        self.listID = listID
        _title = State(initialValue: task.title)
        _note = State(initialValue: task.note)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Task").font(.headline)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Notes (optional)", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Save") {
                    store.updateTask(task.id, in: listID, title: title, note: note)
                    dismiss()
                }
                .disabled(title.isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 300)
    }
}
