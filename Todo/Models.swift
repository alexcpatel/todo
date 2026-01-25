import Foundation

enum TaskStatus: String, Codable {
    case incomplete, completed, wontDo
}

struct TaskList: Identifiable, Codable {
    var id = UUID()
    var name: String
    var order: Int
    var items: [TaskItem]

    init(name: String, order: Int = 0) {
        self.name = name
        self.order = order
        items = []
    }
}

struct TaskItem: Identifiable, Codable {
    var id = UUID()
    var title: String
    var note: String
    var status: TaskStatus
    var completedAt: Date?
    var order: Int

    var isCompleted: Bool { status == .completed }
    var isWontDo: Bool { status == .wontDo }
    var isDone: Bool { status != .incomplete }

    init(title: String, note: String = "", order: Int = 0) {
        self.title = title
        self.note = note
        self.status = .incomplete
        self.order = order
    }

    mutating func complete() {
        status = .completed
        completedAt = Date()
    }

    mutating func markWontDo() {
        status = .wontDo
        completedAt = Date()
    }

    mutating func reopen() {
        status = .incomplete
        completedAt = nil
    }
}
