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
        lastBackupDate = backups.first?.date
    }

    private var iCloudURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
    }

    private var backupURL: URL? {
        if let icloud = iCloudURL {
            let backupDir = icloud.appendingPathComponent("Backups")
            try? FileManager.default.createDirectory(
                at: backupDir,
                withIntermediateDirectories: true
            )
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
        let localData = SaveData(
            lists: lists,
            trashedLists: trashedLists,
            trashedTasks: trashedTasks
        )

        Task.detached {
            var remoteData: SaveData?
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()

            coordinator
                .coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
                    guard let data = try? Data(contentsOf: readURL) else { return }

                    if let decoded = try? JSONDecoder().decode(SaveData.self, from: data) {
                        remoteData = decoded
                    } else if let decoded = try? JSONDecoder().decode([TaskList].self, from: data) {
                        remoteData = SaveData(lists: decoded, trashedLists: [], trashedTasks: [])
                    }
                }

            if checkiCloud, !FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            }

            if let remoteData {
                let merged = Self.merge(local: localData, remote: remoteData)
                await MainActor.run {
                    self.lists = merged.lists.sorted { $0.order < $1.order }
                    self.trashedLists = merged.trashedLists
                    self.trashedTasks = merged.trashedTasks
                }
            }
        }
    }

    // MARK: - Conflict Resolution

    /// Merges local and remote data using version counters (higher version wins)
    private nonisolated static func merge(local: SaveData, remote: SaveData) -> SaveData {
        SaveData(
            lists: mergeLists(local: local.lists, remote: remote.lists),
            trashedLists: mergeLists(local: local.trashedLists, remote: remote.trashedLists),
            trashedTasks: mergeTasks(local: local.trashedTasks, remote: remote.trashedTasks)
        )
    }

    private nonisolated static func mergeLists(
        local: [TaskList],
        remote: [TaskList]
    ) -> [TaskList] {
        var result: [UUID: TaskList] = [:]

        // Add all remote lists
        for list in remote {
            result[list.id] = list
        }

        // Merge local lists (higher version wins, always merge items)
        for var localList in local {
            if var remoteList = result[localList.id] {
                // Always merge items from both sides
                let mergedItems = mergeTasks(local: localList.items, remote: remoteList.items)

                // Higher version wins for list-level properties
                if localList.version > remoteList.version {
                    localList.items = mergedItems
                    // Take max version to preserve causality
                    localList.version = max(localList.version, remoteList.version)
                    result[localList.id] = localList
                } else {
                    remoteList.items = mergedItems
                    remoteList.version = max(localList.version, remoteList.version)
                    result[localList.id] = remoteList
                }
            } else {
                // New local list not in remote
                result[localList.id] = localList
            }
        }

        return Array(result.values)
    }

    private nonisolated static func mergeTasks(
        local: [TaskItem],
        remote: [TaskItem]
    ) -> [TaskItem] {
        var result: [UUID: TaskItem] = [:]

        // Add all remote tasks
        for task in remote {
            result[task.id] = task
        }

        // Merge local tasks (higher version wins)
        for localTask in local {
            if let remoteTask = result[localTask.id] {
                if localTask.version > remoteTask.version {
                    result[localTask.id] = localTask
                }
                // Equal or lower version: keep remote (consistent tiebreaker)
            } else {
                // New local task not in remote
                result[localTask.id] = localTask
            }
        }

        return Array(result.values).sorted { $0.order < $1.order }
    }

    func save() {
        guard let url = fileURL else { return }
        let saveData = SaveData(
            lists: lists,
            trashedLists: trashedLists,
            trashedTasks: trashedTasks
        )
        guard let data = try? JSONEncoder().encode(saveData) else { return }

        coordinatorQueue.async {
            var coordinatorError: NSError?
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(
                writingItemAt: url,
                options: .forReplacing,
                error: &coordinatorError
            ) { writeURL in
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
        guard let files = try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let backupFiles = files
            .filter { $0.pathExtension == "json" }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.creationDateKey]).creationDate) ??
                    .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.creationDateKey]).creationDate) ??
                    .distantPast
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
        guard let files = try? fm.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.creationDateKey]
        ) else {
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
        let saveData = SaveData(
            lists: lists,
            trashedLists: trashedLists,
            trashedTasks: trashedTasks
        )
        guard let data = try? JSONEncoder().encode(saveData) else { return }
        createBackup(data: data)
        lastBackupDate = Date()
    }

    private func startMonitoring() {
        guard iCloudURL != nil else { return }

        metadataQuery = NSMetadataQuery()
        metadataQuery?.predicate = NSPredicate(
            format: "%K == %@",
            NSMetadataItemFSNameKey,
            filename
        )
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
        let uniqueName = makeUniqueName(name)
        let list = TaskList(name: uniqueName, order: lists.count)
        lists.append(list)
        save()
        return list.id
    }

    func renameList(_ id: UUID, to name: String) {
        guard let idx = lists.firstIndex(where: { $0.id == id }) else { return }
        let uniqueName = makeUniqueName(name, excluding: id)
        lists[idx].name = uniqueName
        lists[idx].incrementVersion()
        save()
    }

    private func makeUniqueName(_ name: String, excluding: UUID? = nil) -> String {
        let existingNames = Set(activeLists.filter { $0.id != excluding }.map(\.name))
        if !existingNames.contains(name) { return name }
        var counter = 2
        while existingNames.contains("\(name) \(counter)") {
            counter += 1
        }
        return "\(name) \(counter)"
    }

    func listName(for id: UUID?) -> String? {
        guard let id else { return nil }
        if let list = lists.first(where: { $0.id == id }) { return list.name }
        if let list = trashedLists.first(where: { $0.id == id }) { return list.name }
        return nil
    }

    func canRestoreTask(_ taskID: UUID) -> Bool {
        guard let task = trashedTasks.first(where: { $0.id == taskID }),
              let originalID = task.originalListID else { return false }
        return lists.contains { $0.id == originalID }
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
        for i in lists.indices {
            lists[i].order = i
            lists[i].incrementVersion()
        }
        save()
    }

    // MARK: - Tasks

    @discardableResult
    func addTask(to listID: UUID, title: String, note: String = "") -> UUID? {
        guard let idx = lists.firstIndex(where: { $0.id == listID }) else { return nil }
        let task = TaskItem(title: title, note: note, order: lists[idx].items.count)
        lists[idx].items.append(task)
        lists[idx].incrementVersion()
        save()
        return task.id
    }

    func updateTask(_ taskID: UUID, in listID: UUID, title: String, note: String) {
        guard let listIdx = lists.firstIndex(where: { $0.id == listID }),
              let taskIdx = lists[listIdx].items.firstIndex(where: { $0.id == taskID })
        else { return }
        lists[listIdx].items[taskIdx].title = title
        lists[listIdx].items[taskIdx].note = note
        lists[listIdx].items[taskIdx].incrementVersion()
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
        for i in subset.indices {
            subset[i].order = i
            subset[i].incrementVersion()
        }
        lists[listIdx].items = subset + lists[listIdx].items.filter { $0.isDone != completed }
        save()
    }

    // MARK: - Task Trash

    func restoreTask(_ taskID: UUID) {
        guard let idx = trashedTasks.firstIndex(where: { $0.id == taskID }),
              let listID = trashedTasks[idx].originalListID,
              let listIdx = lists.firstIndex(where: { $0.id == listID }) else { return }
        var task = trashedTasks.remove(at: idx)
        task.restore()
        task.order = lists[listIdx].items.count
        lists[listIdx].items.append(task)
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
