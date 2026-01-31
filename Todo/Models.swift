import Foundation

enum TaskStatus: String, Codable {
    case incomplete, completed, wontDo
}

struct TaskList: Identifiable, Codable {
    var id = UUID()
    var name: String
    var order: Int
    var items: [TaskItem]
    var deletedAt: Date?
    var version: Int = 1

    var isDeleted: Bool { deletedAt != nil }

    init(name: String, order: Int = 0) {
        self.name = name
        self.order = order
        items = []
        version = 1
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        order = try container.decode(Int.self, forKey: .order)
        items = try container.decode([TaskItem].self, forKey: .items)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    mutating func incrementVersion() {
        version += 1
    }

    mutating func moveToTrash() {
        deletedAt = Date()
        incrementVersion()
    }

    mutating func restore() {
        deletedAt = nil
        incrementVersion()
    }
}

struct TaskItem: Identifiable, Codable {
    var id = UUID()
    var title: String
    var note: String
    var status: TaskStatus
    var completedAt: Date?
    var order: Int
    var deletedAt: Date?
    var originalListID: UUID?
    var version: Int = 1

    var isCompleted: Bool { status == .completed }
    var isWontDo: Bool { status == .wontDo }
    var isDone: Bool { status != .incomplete }
    var isDeleted: Bool { deletedAt != nil }

    init(title: String, note: String = "", order: Int = 0) {
        self.title = title
        self.note = note
        self.status = .incomplete
        self.order = order
        version = 1
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        note = try container.decode(String.self, forKey: .note)
        status = try container.decode(TaskStatus.self, forKey: .status)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
        order = try container.decode(Int.self, forKey: .order)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
        originalListID = try container.decodeIfPresent(UUID.self, forKey: .originalListID)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    mutating func incrementVersion() {
        version += 1
    }

    mutating func complete() {
        status = .completed
        completedAt = Date()
        incrementVersion()
    }

    mutating func markWontDo() {
        status = .wontDo
        completedAt = Date()
        incrementVersion()
    }

    mutating func reopen() {
        status = .incomplete
        completedAt = nil
        incrementVersion()
    }

    mutating func moveToTrash(from listID: UUID) {
        deletedAt = Date()
        originalListID = listID
        incrementVersion()
    }

    mutating func restore() {
        deletedAt = nil
        incrementVersion()
    }
}
