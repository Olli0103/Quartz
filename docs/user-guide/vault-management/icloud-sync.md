# iCloud Sync

Quartz Notes supports iCloud Drive for syncing your vault across Apple devices.

## How iCloud sync works

When your vault is stored in iCloud Drive, macOS automatically syncs file changes to all devices signed into the same Apple ID. Quartz Notes monitors the sync status and shows it in the sidebar.

## Setting up iCloud sync

1. Ensure iCloud Drive is enabled in **System Settings > Apple ID > iCloud > iCloud Drive**
2. Create or move your vault to a folder inside iCloud Drive
3. Open that folder as your vault in Quartz Notes

Quartz Notes will automatically detect that the vault is in iCloud Drive and begin monitoring sync status.

## Sync status indicators

The sidebar shows the current sync status:

| Status | Meaning |
|--------|---------|
| **Current** | All files are synced |
| **Syncing** | Files are being uploaded or downloaded |
| **Error** | A sync conflict or connectivity issue |

## Handling files not yet downloaded

iCloud Drive may evict files from local storage to save disk space (the "Optimize Mac Storage" setting). If you try to open a note that hasn't been downloaded yet, Quartz Notes shows an error message:

> "[filename] is not downloaded from iCloud. Open Finder and wait for it to sync, then try again."

A **Try Again** button lets you retry once the file downloads.

**Tip:** To ensure all files are available offline, disable **Optimize Mac Storage** in System Settings > Apple ID > iCloud > iCloud Drive.

## Sync conflicts

If the same note is edited on two devices before syncing, iCloud creates conflict copies. Quartz Notes detects these and shows a conflict resolution banner.

## Limitations

- iCloud sync is controlled by macOS, not by Quartz Notes. Sync speed depends on your internet connection and Apple's infrastructure.
- Large vaults (1000+ notes) may take time for initial sync.
- The "Optimize Mac Storage" feature can cause files to be unavailable until downloaded.

---

**Next:** [Backup & Restore](backup-and-restore.md)
