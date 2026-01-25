import Combine
import Foundation

@MainActor
final class Store: ObservableObject {
    @Published var lists: [TaskList] = []

    private let filename = "todo-data.json"
    private var metadataQuery: NSMetadataQuery?

    init() {
        load()
        startMonitoring()
    }

    // MARK: - iCloud Drive URL

    private var iCloudURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    private var fileURL: URL? {
        if let icloud = iCloudURL {
            try? FileManager.default.createDirectory(at: icloud, withIntermediateDirectories: true)
            return icloud.appendingPathComponent(filename)
        }
        // Fallback to local
        let local = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return local.appendingPathComponent(filename)
    }

    // MARK: - Persistence

    func load() {
        guard let url = fileURL else { return }

        // Download if in iCloud
        if !FileManager.default.isUbiquitousItem(at: url)
            || FileManager.default.fileExists(atPath: url.path)
        {
            readFile(at: url)
        } else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    private func readFile(at url: URL) {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([TaskList].self, from: data)
        else { return }
        lists = decoded.sorted { $0.order < $1.order }
    }

    func save() {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(lists)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: - iCloud Monitoring

    private func startMonitoring() {
        guard iCloudURL != nil else { return }

        metadataQuery = NSMetadataQuery()
        metadataQuery?.predicate = NSPredicate(
            format: "%K == %@", NSMetadataItemFSNameKey, filename
        )
        metadataQuery?.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]

        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate, object: metadataQuery
        )
        metadataQuery?.start()
    }

    @objc private func queryDidUpdate() {
        Task { @MainActor in
            load()
        }
    }

    // MARK: - List Operations

    func addList(name: String) {
        lists.append(TaskList(name: name, order: lists.count))
        save()
    }

    func deleteList(_ list: TaskList) {
        lists.removeAll { $0.id == list.id }
        save()
    }

    func moveList(from: IndexSet, to: Int) {
        lists.move(fromOffsets: from, toOffset: to)
        for (i, _) in lists.enumerated() {
            lists[i].order = i
        }
        save()
    }

    // MARK: - Task Operations

    func addTask(to listID: UUID, title: String) {
        guard let idx = lists.firstIndex(where: { $0.id == listID }) else { return }
        let task = TaskItem(title: title, order: lists[idx].items.count)
        lists[idx].items.append(task)
        save()
    }

    func toggleTask(_ taskID: UUID, in listID: UUID) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }),
              let taskIdx = lists[listIdx].items.firstIndex(where: { $0.id == taskID })
        else { return }
        if lists[listIdx].items[taskIdx].isCompleted {
            lists[listIdx].items[taskIdx].uncomplete()
        } else {
            lists[listIdx].items[taskIdx].complete()
        }
        save()
    }

    func deleteTask(_ taskID: UUID, from listID: UUID) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[listIdx].items.removeAll { $0.id == taskID }
        save()
    }

    func moveTasks(in listID: UUID, completed: Bool, from: IndexSet, to: Int) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }) else { return }
        var subset = lists[listIdx].items.filter { $0.isCompleted == completed }
        subset.move(fromOffsets: from, toOffset: to)
        for (i, _) in subset.enumerated() {
            subset[i].order = i
        }

        let other = lists[listIdx].items.filter { $0.isCompleted != completed }
        lists[listIdx].items = subset + other
        save()
    }
}
