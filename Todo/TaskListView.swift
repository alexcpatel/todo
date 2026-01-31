import SwiftUI
#if os(macOS)
import AppKit
#else
import AudioToolbox
#endif

enum CompletionSound: String, CaseIterable, Identifiable {
    // Original macOS sound names
    case none = "None"
    case glass = "Glass"
    case pop = "Pop"
    case hero = "Hero"
    case ping = "Ping"
    case tink = "Tink"
    case purr = "Purr"
    case blow = "Blow"
    case morse = "Morse"
    case sosumi = "Sosumi"
    case funk = "Funk"
    case submarine = "Submarine"
    case basso = "Basso"

    var id: String { rawValue }

    static var availableCases: [CompletionSound] {
        #if os(iOS)
        return allCases.filter { $0 != .submarine }
        #else
        return allCases.map { $0 }
        #endif
    }

    #if os(iOS)
    private var systemSoundID: SystemSoundID {
        switch self {
        case .none: return 0
        case .glass: return 1336        // subtle glass tap
        case .pop: return 1306          // light pop
        case .hero: return 1335         // ascending success
        case .ping: return 1340         // clean ping
        case .tink: return 1105         // light tink
        case .purr: return 1311         // soft purr
        case .blow: return 1320         // airy blow
        case .morse: return 1312        // short morse
        case .sosumi: return 1323       // melodic note
        case .funk: return 1310         // funky tone
        case .submarine: return 1313    // deep tone
        case .basso: return 1308        // bass note
        }
    }
    #endif

    func play() {
        guard self != .none else { return }
        #if os(macOS)
        NSSound(named: rawValue)?.play()
        #else
        AudioServicesPlaySystemSound(systemSoundID)
        #endif
    }
}

@MainActor
struct SoundSettings {
    @AppStorage("completionSound") static var selectedSound: String = CompletionSound.hero.rawValue

    static var current: CompletionSound {
        CompletionSound(rawValue: selectedSound) ?? .hero
    }
}

@MainActor
private func playCompletionSound() {
    SoundSettings.current.play()
}

struct TaskListView: View {
    let list: TaskList
    @EnvironmentObject var store: Store
    @State private var scrollTarget: UUID?

    private var incompleteTasks: [TaskItem] {
        list.items.filter { !$0.isDone }.sorted { $0.order < $1.order }
    }

    private var doneTasks: [TaskItem] {
        list.items.filter(\.isDone).sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    ForEach(incompleteTasks) { task in
                        TaskRow(task: task, listID: list.id)
                            .id(task.id)
                    }
                    .onMove { store.moveTasks(in: list.id, completed: false, from: $0, to: $1) }
                    .onDelete { indices in
                        for i in indices { store.deleteTask(incompleteTasks[i].id, from: list.id) }
                    }

                    NewTaskRow(listID: list.id, onAdd: { id in
                        scrollTarget = id
                    })
                    .id("newTask")
                    .transaction { $0.animation = nil }
                } header: {
                    Text("Tasks").font(.subheadline.weight(.medium))
                }

                if !doneTasks.isEmpty {
                    Section {
                        ForEach(doneTasks) { task in
                            TaskRow(task: task, listID: list.id)
                                .id(task.id)
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
            .onChange(of: scrollTarget) { _, target in
                if let target {
                    withAnimation {
                        proxy.scrollTo(target, anchor: .center)
                    }
                    scrollTarget = nil
                }
            }
        }
        #if os(iOS)
        .listStyle(.plain)
        .listSectionSpacing(.compact)
        .contentMargins(.top, 0, for: .scrollContent)
        .toolbar { EditButton() }
        .scrollDismissesKeyboard(.interactively)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        #endif
        .id(list.id)
        .navigationTitle(list.name)
    }
}

struct NewTaskRow: View {
    let listID: UUID
    var onAdd: ((UUID) -> Void)? = nil
    @EnvironmentObject var store: Store
    @State private var title = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square")
                .font(.title2)
                .foregroundStyle(.quaternary)

            TextField("Add a task...", text: $title)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit {
                    guard !title.isEmpty else { return }
                    let id = store.addTask(to: listID, title: title)
                    title = ""
                    isFocused = true
                    if let id { onAdd?(id) }
                }
        }
        .padding(.vertical, 4)
        #if os(iOS)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isFocused = false }
            }
        }
        #endif
    }
}

struct TaskRow: View {
    let task: TaskItem
    let listID: UUID
    @EnvironmentObject var store: Store
    @State private var editedTitle: String = ""
    @State private var isEditing = false
    @State private var isEditingNote = false
    @State private var editedNote: String = ""
    @FocusState private var isFocused: Bool
    @FocusState private var isNoteFocused: Bool

    private var icon: String {
        switch task.status {
        case .incomplete: return "square"
        case .completed: return "checkmark.square.fill"
        case .wontDo: return "minus.square.fill"
        }
    }

    private var iconColor: Color {
        switch task.status {
        case .incomplete: return .secondary
        case .completed: return .secondary
        case .wontDo: return .gray
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                let newStatus: TaskStatus = task.isDone ? .incomplete : .completed
                withAnimation(.smooth(duration: 0.3)) {
                    store.setTaskStatus(task.id, in: listID, status: newStatus)
                }
                if newStatus == .completed { playCompletionSound() }
            } label: {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .symbolEffect(.bounce, value: task.status)
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.impact(weight: .light), trigger: task.status)

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

                if !task.note.isEmpty || isEditingNote {
                    if isEditingNote {
                        TextField("Add a note...", text: $editedNote, axis: .vertical)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .textFieldStyle(.plain)
                            .focused($isNoteFocused)
                            .onSubmit { saveNote() }
                            .onChange(of: isNoteFocused) { _, focused in
                                if !focused { saveNote() }
                            }
                    } else {
                        Text(task.note)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .onTapGesture { startEditingNote() }
                    }
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
            Button(task.note.isEmpty ? "Add Note" : "Edit Note") { startEditingNote() }
            Divider()
            if task.status != .completed {
                Button("Complete") {
                    store.setTaskStatus(task.id, in: listID, status: .completed)
                    playCompletionSound()
                }
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
            Button {
                store.setTaskStatus(task.id, in: listID, status: .completed)
                playCompletionSound()
            } label: {
                Label("Complete", systemImage: "checkmark")
            }
            .tint(.green)
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

    private func startEditingNote() {
        editedNote = task.note
        isEditingNote = true
        isNoteFocused = true
    }

    private func saveNote() {
        let text = editedNote.trimmingCharacters(in: .whitespaces)
        if text != task.note {
            store.updateTask(task.id, in: listID, title: task.title, note: text)
        }
        isEditingNote = false
    }
}
