# Backup & Restore

Quartz Notes can create compressed backups of your entire vault and restore from them if needed.

## Creating a backup

1. Open **Settings > Data & Sync**
2. Click **Create Backup**
3. Choose a destination (or use the default backup location)

Backups are saved as ZIP archives with a timestamp in the filename.

## Auto-backup

Enable automatic backups in **Settings > Data & Sync > Auto-Backup**. When enabled, Quartz Notes creates a backup periodically and keeps the 7 most recent backups, automatically deleting older ones.

## Restoring from a backup

1. Open **Settings > Data & Sync**
2. In the **Backups** section, select a backup from the list
3. Click **Restore**
4. Choose a destination folder

The restore extracts the backup archive to the chosen folder. Your current vault is not modified — the restore creates a new copy.

## Backup contents

A backup includes:
- All `.md` note files
- All folders and subfolders
- Assets and attachments
- Frontmatter and metadata

A backup does **not** include:
- The search index (rebuilt automatically)
- The preview cache (rebuilt automatically)
- AI embeddings (re-indexed on next vault open)

## Best practices

- Keep backups on a different drive than your vault
- Test restoring a backup occasionally to verify it works
- If using iCloud, also keep a local backup as a safety net

---

**Next:** [AI Overview](../ai-features/overview.md)
