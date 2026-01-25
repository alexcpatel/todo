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

    private var iCloudURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    private var fileURL: URL? {
        if let icloud = iCloudURL {
            try? FileManager.default.createDirectory(at: icloud, withIntermediateDirectories: true)
            return icloud.appendingPathComponent(filename)
        }
        let local = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return local.appendingPathComponent(filename)
    }

    func load() {
        guard let url = fileURL else { return }
        if !FileManager.default.isUbiquitousItem(at: url)
            || FileManager.default.fileExists(atPath: url.path)
        {
            if let data = try? Data(contentsOf: url),
               let decoded = try? JSONDecoder().decode([TaskList].self, from: data)
            {
                lists = decoded.sorted { $0.order < $1.order }
            }
        } else {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
    }

    func save() {
        guard let url = fileURL,
              let data = try? JSONEncoder().encode(lists)
        else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func startMonitoring() {
        guard iCloudURL != nil else { return }
        metadataQuery = NSMetadataQuery()
        metadataQuery?.predicate = NSPredicate(format: "%K == %@", NSMetadataItemFSNameKey, filename)
        metadataQuery?.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidUpdate),
            name: .NSMetadataQueryDidUpdate, object: metadataQuery
        )
        metadataQuery?.start()
    }

    @objc private func queryDidUpdate() {
        Task { @MainActor in load() }
    }

    // MARK: - Lists

    func addList(name: String) -> UUID {
        let list = TaskList(name: name, order: lists.count)
        lists.append(list)
        save()
        return list.id
    }

    func renameList(_ id: UUID, to name: String) {
        guard let idx = lists.firstIndex(where: { $0.id == id }) else { return }
        lists[idx].name = name
        save()
    }

    func deleteList(_ id: UUID) {
        lists.removeAll { $0.id == id }
        save()
    }

    func moveList(from: IndexSet, to: Int) {
        lists.move(fromOffsets: from, toOffset: to)
        for i in lists.indices { lists[i].order = i }
        save()
    }

    // MARK: - Tasks

    func addTask(to listID: UUID, title: String, note: String = "") {
        guard let idx = lists.firstIndex(where: { $0.id == listID }) else { return }
        lists[idx].items.append(TaskItem(title: title, note: note, order: lists[idx].items.count))
        save()
    }

    func updateTask(_ taskID: UUID, in listID: UUID, title: String, note: String) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }),
              let taskIdx = lists[listIdx].items.firstIndex(where: { $0.id == taskID })
        else { return }
        lists[listIdx].items[taskIdx].title = title
        lists[listIdx].items[taskIdx].note = note
        save()
    }

    func setTaskStatus(_ taskID: UUID, in listID: UUID, status: TaskStatus) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }),
              let taskIdx = lists[listIdx].items.firstIndex(where: { $0.id == taskID })
        else { return }
        switch status {
        case .incomplete: lists[listIdx].items[taskIdx].reopen()
        case .completed: lists[listIdx].items[taskIdx].complete()
        case .wontDo: lists[listIdx].items[taskIdx].markWontDo()
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
        var subset = lists[listIdx].items.filter { $0.isDone == completed }
        subset.move(fromOffsets: from, toOffset: to)
        for i in subset.indices { subset[i].order = i }
        lists[listIdx].items = subset + lists[listIdx].items.filter { $0.isDone != completed }
        save()
    }
}
