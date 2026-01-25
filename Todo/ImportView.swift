import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @EnvironmentObject var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Import from TickTick")
                .font(.title2.bold())

            Text(
                "Export your data from TickTick:\n1. Go to ticktick.com\n2. Settings → Account → Generate Backup\n3. Download the CSV file"
            )
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)

            Button("Select CSV File") { importing = true }
                .buttonStyle(.borderedProminent)

            if let error { Text(error).foregroundStyle(.red).font(.caption) }

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
        }
        .padding(40)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText]) {
            result in
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
                guard row.count >= 5 else { continue }
                let listName = row[0].isEmpty ? "Inbox" : row[0]
                let title = row[1]
                let status = row[3].lowercased()
                let completedStr = row.count > 10 ? row[10] : ""

                guard !title.isEmpty else { continue }

                let listIdx: Int
                if let idx = listCache[listName] {
                    listIdx = idx
                } else {
                    store.lists.append(TaskList(name: listName, order: store.lists.count))
                    listIdx = store.lists.count - 1
                    listCache[listName] = listIdx
                }

                var task = TaskItem(title: title, order: store.lists[listIdx].items.count)
                if status == "completed" || status == "2" {
                    task.isCompleted = true
                    task.completedAt = parseDate(completedStr) ?? Date()
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
                if !current.allSatisfy(\.isEmpty) { rows.append(current) }
                current = []
                field = ""
            } else {
                field.append(char)
            }
        }
        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            rows.append(current)
        }
        return rows.dropFirst().map { $0 }
    }

    private func parseDate(_ str: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: str) ?? ISO8601DateFormatter().date(from: str)
    }
}
