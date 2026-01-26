# Todo

A native macOS/iOS todo app with iCloud sync.

![Screenshot](screenshot.png)

## Features

- Named lists with tasks
- Check/uncheck tasks with completion dates
- Reorder tasks and lists
- Trash with restore capability
- Automatic backups (every 5 min, keeps last 20)
- iCloud Drive sync between devices
- Import/Export from TickTick (macOS)

## How It Works

### Architecture

```
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

The sync follows **eventual consistency** with **last-writer-wins (LWW)** conflict resolution—a pragmatic tradeoff described in *Designing Data-Intensive Applications* (Kleppmann, Ch. 5).

| Aspect | Approach |
|--------|----------|
| Replication | Single-leader (file as source of truth) |
| Conflict resolution | Last-writer-wins (iCloud handles) |
| Consistency | Eventual (seconds to minutes lag) |
| Durability | Local + iCloud redundancy + auto-backups |

**Tradeoffs**: LWW can lose concurrent edits. For a personal todo app with single-user-per-device usage, this is acceptable. A multi-user collaborative app would need CRDTs or operational transformation.

### Backup Strategy

Automatic timestamped backups are created every 5 minutes (on save), stored in `Backups/` within the same iCloud container. Old backups are pruned to keep the last 20. Restore available in Settings.

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
