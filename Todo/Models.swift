import Foundation

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
    var isCompleted: Bool
    var completedAt: Date?
    var order: Int

    init(title: String, order: Int = 0) {
        self.title = title
        isCompleted = false
        self.order = order
    }

    mutating func complete() {
        isCompleted = true
        completedAt = Date()
    }

    mutating func uncomplete() {
        isCompleted = false
        completedAt = nil
    }
}
