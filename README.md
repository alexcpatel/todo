# Todo

A native macOS/iOS todo app with iCloud sync.

![Screenshot](screenshot.png)

## Features

- Named lists with tasks
- Check/uncheck tasks with completion dates
- Reorder tasks and lists
- Trash with restore capability
- Automatic backups (hourly, keeps last 30)
- iCloud Drive sync between devices
- Import from TickTick (macOS)

## How It Works

### Architecture

```bash
┌─────────────┐     ┌─────────────────┐     ┌─────────────┐
│   iPhone    │────▶│   iCloud Drive  │◀────│     Mac     │
│   (Store)   │◀────│  (JSON file)    │────▶│   (Store)   │
└─────────────┘     └─────────────────┘     └─────────────┘
```

### Storage & Sync

Data is stored as a single JSON file (`todo-data.json`) in iCloud Drive's ubiquity container. Each device runs an independent `Store` that:

1. **Reads/writes** via `NSFileCoordinator` for safe concurrent access
2. **Monitors changes** via `NSMetadataQuery` to detect remote updates
3. **Reloads automatically** when iCloud notifies of external changes

### Consistency Model

The sync follows **eventual consistency** with **version-based merge** conflict resolution.

| Aspect | Approach |
| -------- | ---------- |
| Replication | Multi-leader (each device writes independently) |
| Conflict resolution | Version counters (higher version wins, merge at item level) |
| Consistency | Eventual (seconds to minutes lag) |
| Durability | Local + iCloud redundancy + auto-backups |

**How merging works:**

- Each list and task has a version counter, incremented on every modification
- When syncing, items are merged by ID: higher version wins
- New items from either side are preserved (add-wins semantics)
- Concurrent edits to different items never conflict

**Tradeoffs**: Concurrent edits to the *same* item will resolve to the higher version. For a personal todo app this is acceptable—conflicts are rare and hourly backups provide recovery.

### Backup Strategy

Automatic timestamped backups are created hourly, stored in `Backups/` within the same iCloud container. Old backups are pruned to keep the last 30 (~30 days of coverage).

**Restore:** File → Restore from Backup → select a date/time

## Requirements

- macOS 15+ / iOS 18+
- Xcode 16+
- Apple Developer account (free works)

## Build

```bash
cp build.example.sh build.sh
# Edit build.sh with your device ID (find with: xcrun xctrace list devices)
chmod +x build.sh

./build.sh mac      # Build and run on Mac
./build.sh iphone   # Build and run on iPhone
./build.sh both     # Both simultaneously
./build.sh clean    # Clean build artifacts
```

## Import from TickTick

1. Export from TickTick (Settings → Backup → Export to CSV)
2. In app: File → Import from TickTick...
3. Select the CSV file
