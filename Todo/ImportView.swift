import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Import from TickTick").font(.title2.bold())

            Text("1. Go to ticktick.com\n2. Settings → Account → Generate Backup\n3. Download the CSV file")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Select CSV File") { importing = true }
                .buttonStyle(.borderedProminent)

            if let error {
                Text(error).foregroundStyle(.red).font(.caption)
            }

            Button("Cancel") { dismiss() }.buttonStyle(.bordered)
        }
        .padding(40)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText]) { result in
            switch result {
            case let .success(url): importCSV(from: url)
            case let .failure(err): error = err.localizedDescription
            }
        }
    }

    private func importCSV(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            error = "Cannot access file"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let rows = parseCSV(content)

            var listCache: [String: Int] = [:]

            for row in rows {
                // CSV: 0=Folder, 1=List, 2=Title, 5=Content, 12=Status, 14=Completed Time
                guard row.count >= 13 else { continue }

                let listName = row[1].trimmingCharacters(in: .whitespaces)
                let title = row[2].trimmingCharacters(in: .whitespaces)
                let note = row.count > 5 ? row[5].trimmingCharacters(in: .whitespaces) : ""
                let statusStr = row[12].trimmingCharacters(in: .whitespaces)
                let completedStr = row.count > 14 ? row[14] : ""

                guard !title.isEmpty, !listName.isEmpty else { continue }

                let listIdx: Int
                if let idx = listCache[listName] {
                    listIdx = idx
                } else {
                    store.lists.append(TaskList(name: listName, order: store.lists.count))
                    listIdx = store.lists.count - 1
                    listCache[listName] = listIdx
                }

                var task = TaskItem(title: title, note: note, order: store.lists[listIdx].items.count)
                // Status: 0=Normal, 1=Completed, 2=Archived, -1=Won't Do
                switch statusStr {
                case "1", "2":
                    task.status = .completed
                    task.completedAt = parseDate(completedStr) ?? Date()
                case "-1":
                    task.status = .wontDo
                    task.completedAt = parseDate(completedStr) ?? Date()
                default:
                    task.status = .incomplete
                }
                store.lists[listIdx].items.append(task)
            }

            store.save()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func parseCSV(_ content: String) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false

        for char in content {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == ",", !inQuotes {
                current.append(field)
                field = ""
            } else if char == "\n", !inQuotes {
                current.append(field)
                if current.count > 3 { rows.append(current) }
                current = []
                field = ""
            } else {
                field.append(char)
            }
        }
        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            if current.count > 3 { rows.append(current) }
        }
        // Skip header rows (first 7 lines are metadata)
        return Array(rows.dropFirst(7))
    }

    private func parseDate(_ str: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: str)
    }
}

struct ExportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var exporting = false

    var body: some View {
        VStack(spacing: 20) {
            Text("Export to TickTick").font(.title2.bold())

            Text("Export your lists as a CSV file compatible with TickTick import.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Export CSV") { exporting = true }
                .buttonStyle(.borderedProminent)

            Button("Cancel") { dismiss() }.buttonStyle(.bordered)
        }
        .padding(40)
        .fileExporter(
            isPresented: $exporting,
            document: TickTickCSV(lists: store.lists),
            contentType: .commaSeparatedText,
            defaultFilename: "todo-export.csv"
        ) { _ in dismiss() }
    }
}

struct TickTickCSV: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let lists: [TaskList]

    init(lists: [TaskList]) {
        self.lists = lists
    }

    init(configuration: ReadConfiguration) throws {
        lists = []
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        var csv = "\"Folder Name\",\"List Name\",\"Title\",\"Kind\",\"Tags\",\"Content\",\"Is Check list\",\"Start Date\",\"Due Date\",\"Reminder\",\"Repeat\",\"Priority\",\"Status\",\"Created Time\",\"Completed Time\",\"Order\",\"Timezone\",\"Is All Day\",\"Is Floating\",\"Column Name\",\"Column Order\",\"View Mode\",\"taskId\",\"parentId\"\n"

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]

        for list in lists {
            for (idx, task) in list.items.enumerated() {
                let status: String
                switch task.status {
                case .incomplete: status = "0"
                case .completed: status = "1"
                case .wontDo: status = "-1"
                }

                let completedTime = task.completedAt.map { dateFormatter.string(from: $0) } ?? ""
                let createdTime = dateFormatter.string(from: Date())

                let row = [
                    "", // Folder
                    list.name,
                    task.title,
                    "TEXT",
                    "", // Tags
                    task.note,
                    "N",
                    "", // Start Date
                    "", // Due Date
                    "", // Reminder
                    "", // Repeat
                    "0", // Priority
                    status,
                    createdTime,
                    completedTime,
                    "\(idx)",
                    "America/New_York",
                    "false",
                    "false",
                    "", // Column Name
                    "", // Column Order
                    "list",
                    UUID().uuidString,
                    ""
                ]
                csv += row.map { "\"\($0)\"" }.joined(separator: ",") + "\n"
            }
        }

        return FileWrapper(regularFileWithContents: csv.data(using: .utf8)!)
    }
}
