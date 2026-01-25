import SwiftUI

struct TaskListView: View {
    let list: TaskList
    @EnvironmentObject var store: Store
    @State private var newTaskTitle = ""

    private var incompleteTasks: [TaskItem] {
        list.items.filter { !$0.isCompleted }.sorted { $0.order < $1.order }
    }

    private var completedTasks: [TaskItem] {
        list.items.filter(\.isCompleted).sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }

    var body: some View {
        List {
            Section("Tasks") {
                ForEach(incompleteTasks) { task in
                    TaskRow(task: task, listID: list.id)
                }
                .onMove { store.moveTasks(in: list.id, completed: false, from: $0, to: $1) }
                .onDelete { indices in
                    for i in indices {
                        store.deleteTask(incompleteTasks[i].id, from: list.id)
                    }
                }

                HStack {
                    TextField("New task", text: $newTaskTitle)
                        .textFieldStyle(.plain)
                        .onSubmit(addTask)
                    Button(action: addTask) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .disabled(newTaskTitle.isEmpty)
                }
                .padding(.vertical, 4)
            }

            if !completedTasks.isEmpty {
                Section("Completed") {
                    ForEach(completedTasks) { task in
                        TaskRow(task: task, listID: list.id)
                    }
                    .onMove { store.moveTasks(in: list.id, completed: true, from: $0, to: $1) }
                    .onDelete { indices in
                        for i in indices {
                            store.deleteTask(completedTasks[i].id, from: list.id)
                        }
                    }
                }
            }
        }
        .navigationTitle(list.name)
        #if os(iOS)
            .toolbar { EditButton() }
        #endif
    }

    private func addTask() {
        guard !newTaskTitle.isEmpty else { return }
        store.addTask(to: list.id, title: newTaskTitle)
        newTaskTitle = ""
    }
}

struct TaskRow: View {
    let task: TaskItem
    let listID: UUID
    @EnvironmentObject var store: Store

    var body: some View {
        HStack {
            Button {
                withAnimation { store.toggleTask(task.id, in: listID) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
            }
            .buttonStyle(.plain)

            Text(task.title)
                .strikethrough(task.isCompleted)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)

            Spacer()

            if task.isCompleted, let date = task.completedAt {
                Text(date, style: .date)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contextMenu {
            Button("Delete", role: .destructive) { store.deleteTask(task.id, from: listID) }
        }
    }
}
