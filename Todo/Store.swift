import Combine
import Foundation

@MainActor
final class Store: ObservableObject {
    @Published var lists: [TaskList] = []
    @Published var trashedLists: [TaskList] = []
    @Published var trashedTasks: [TaskItem] = []
    @Published var syncStatus: String = "Checking..."
    @Published var backups: [BackupInfo] = []

    private let filename = "todo-data.json"
    private let maxBackups = 30
    private let backupInterval: TimeInterval = 3600 // 1 hour
    private var metadataQuery: NSMetadataQuery?
    private var coordinatorQueue = DispatchQueue(label: "com.todo.filecoordinator")
    private var lastBackupDate: Date?

    struct BackupInfo: Identifiable {
        let id: String
        let date: Date
        let url: URL
    }

    var activeLists: [TaskList] {
        lists.filter { !$0.isDeleted }.sorted { $0.order < $1.order }
    }

    var trashCount: Int {
        trashedLists.count + trashedTasks.count
    }

    init() {
        load()
        startMonitoring()
        updateSyncStatus()
        loadBackupsList()
    }

    private var iCloudURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    private var backupURL: URL? {
        if let icloud = iCloudURL {
            let backupDir = icloud.appendingPathComponent("Backups")
            try? FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
            return backupDir
        }
        let local = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups")
        try? FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        return local
    }

    private var fileURL: URL? {
        if let icloud = iCloudURL {
            try? FileManager.default.createDirectory(at: icloud, withIntermediateDirectories: true)
            return icloud.appendingPathComponent(filename)
        }
        let local = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return local.appendingPathComponent(filename)
    }

    var isUsingiCloud: Bool { iCloudURL != nil }

    func updateSyncStatus() {
        syncStatus = iCloudURL != nil ? "iCloud" : "Local only"
    }

    private struct SaveData: Codable {
        var lists: [TaskList]
        var trashedLists: [TaskList]
        var trashedTasks: [TaskItem]
    }

    func load() {
        guard let url = fileURL else { return }
        let checkiCloud = isUsingiCloud

        Task.detached {
            var result: SaveData?
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()

            coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
                guard let data = try? Data(contentsOf: readURL) else { return }

                if let decoded = try? JSONDecoder().decode(SaveData.self, from: data) {
                    result = SaveData(
                        lists: decoded.lists.sorted { $0.order < $1.order },
                        trashedLists: decoded.trashedLists,
                        trashedTasks: decoded.trashedTasks
                    )
                } else if let decoded = try? JSONDecoder().decode([TaskList].self, from: data) {
                    result = SaveData(
                        lists: decoded.sorted { $0.order < $1.order },
                        trashedLists: [],
                        trashedTasks: []
                    )
                }
            }

            if checkiCloud, !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }

            if let result {
                await MainActor.run { [result] in
                    self.lists = result.lists
                    self.trashedLists = result.trashedLists
                    self.trashedTasks = result.trashedTasks
                }
            }
        }
    }

    func save() {
        guard let url = fileURL else { return }
        let saveData = SaveData(lists: lists, trashedLists: trashedLists, trashedTasks: trashedTasks)
        guard let data = try? JSONEncoder().encode(saveData) else { return }

        coordinatorQueue.async {
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) { writeURL in
                try? data.write(to: writeURL, options: .atomic)
            }
        }

        // Create backup hourly
        let now = Date()
        if lastBackupDate == nil || now.timeIntervalSince(lastBackupDate!) > backupInterval {
            createBackup(data: data)
            lastBackupDate = now
        }
    }

    // MARK: - Backups

    private func createBackup(data: Data) {
        guard let backupDir = backupURL else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let timestamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupFile = backupDir.appendingPathComponent("backup-\(timestamp).json")

        coordinatorQueue.async { [weak self] in
            try? data.write(to: backupFile, options: .atomic)
            Task { @MainActor in
                self?.cleanupOldBackups()
                self?.loadBackupsList()
            }
        }
    }

    private func cleanupOldBackups() {
        guard let backupDir = backupURL else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey]) else { return }

        let backupFiles = files
            .filter { $0.pathExtension == "json" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return date1 > date2
            }

        if backupFiles.count > maxBackups {
            for file in backupFiles.dropFirst(maxBackups) {
                try? fm.removeItem(at: file)
            }
        }
    }

    func loadBackupsList() {
        guard let backupDir = backupURL else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: backupDir, includingPropertiesForKeys: [.creationDateKey]) else {
            backups = []
            return
        }

        backups = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> BackupInfo? in
                guard let values = try? url.resourceValues(forKeys: [.creationDateKey]),
                      let date = values.creationDate else { return nil }
                return BackupInfo(id: url.lastPathComponent, date: date, url: url)
            }
            .sorted { $0.date > $1.date }
    }

    func restoreBackup(_ backup: BackupInfo) {
        guard let data = try? Data(contentsOf: backup.url),
              let decoded = try? JSONDecoder().decode(SaveData.self, from: data) else { return }

        lists = decoded.lists.sorted { $0.order < $1.order }
        trashedLists = decoded.trashedLists
        trashedTasks = decoded.trashedTasks
        save()
    }

    func deleteBackup(_ backup: BackupInfo) {
        try? FileManager.default.removeItem(at: backup.url)
        loadBackupsList()
    }

    func createManualBackup() {
        let saveData = SaveData(lists: lists, trashedLists: trashedLists, trashedTasks: trashedTasks)
        guard let data = try? JSONEncoder().encode(saveData) else { return }
        createBackup(data: data)
        lastBackupDate = Date()
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
        NotificationCenter.default.addObserver(
            self, selector: #selector(queryDidFinishGathering),
            name: .NSMetadataQueryDidFinishGathering, object: metadataQuery
        )

        metadataQuery?.start()
    }

    @objc private func queryDidUpdate(_ notification: Notification) {
        Task { @MainActor in load() }
    }

    @objc private func queryDidFinishGathering(_ notification: Notification) {
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
        guard let idx = lists.firstIndex(where: { $0.id == id }) else { return }
        var list = lists.remove(at: idx)
        list.moveToTrash()
        trashedLists.append(list)
        save()
    }

    func restoreList(_ id: UUID) {
        guard let idx = trashedLists.firstIndex(where: { $0.id == id }) else { return }
        var list = trashedLists.remove(at: idx)
        list.restore()
        list.order = lists.count
        lists.append(list)
        save()
    }

    func permanentlyDeleteList(_ id: UUID) {
        trashedLists.removeAll { $0.id == id }
        save()
    }

    func moveList(from: IndexSet, to: Int) {
        lists.move(fromOffsets: from, toOffset: to)
        for i in lists.indices { lists[i].order = i }
        save()
    }

    // MARK: - Tasks

    @discardableResult
    func addTask(to listID: UUID, title: String, note: String = "") -> UUID? {
        guard let idx = lists.firstIndex(where: { $0.id == listID }) else { return nil }
        let task = TaskItem(title: title, note: note, order: lists[idx].items.count)
        lists[idx].items.append(task)
        save()
        return task.id
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
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }),
              let taskIdx = lists[listIdx].items.firstIndex(where: { $0.id == taskID })
        else { return }
        var task = lists[listIdx].items.remove(at: taskIdx)
        task.moveToTrash(from: listID)
        trashedTasks.append(task)
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

    // MARK: - Task Trash

    func restoreTask(_ taskID: UUID) {
        guard let idx = trashedTasks.firstIndex(where: { $0.id == taskID }) else { return }
        var task = trashedTasks.remove(at: idx)
        task.restore()

        // Find original list or first available
        let targetListID = task.originalListID
        if let listID = targetListID, let listIdx = lists.firstIndex(where: { $0.id == listID }) {
            task.order = lists[listIdx].items.count
            lists[listIdx].items.append(task)
        } else if !lists.isEmpty {
            task.order = lists[0].items.count
            lists[0].items.append(task)
        }
        save()
    }

    func permanentlyDeleteTask(_ taskID: UUID) {
        trashedTasks.removeAll { $0.id == taskID }
        save()
    }

    func emptyTrash() {
        trashedLists.removeAll()
        trashedTasks.removeAll()
        save()
    }
}
