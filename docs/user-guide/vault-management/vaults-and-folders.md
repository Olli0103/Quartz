# Vaults & Folders

Quartz Notes organizes your notes in a simple folder-based system. Every note is a plain `.md` file on your file system.

## Vault structure

A vault is just a folder. Inside it, you can create any folder hierarchy you want:

```
My Vault/
├── Projects/
│   ├── App Launch.md
│   └── Research Paper.md
├── Areas/
│   ├── Health.md
│   └── Finance.md
├── Daily Notes/
│   ├── Daily Note 2026-03-27.md
│   └── Daily Note 2026-03-26.md
└── Inbox.md
```

## Creating folders

1. Click the **ellipsis menu** (three dots) at the top of the sidebar
2. Select **New Folder**
3. Type the folder name and press Enter

Or press **Cmd+Shift+N**.

## Creating notes

1. Press **Cmd+N** or click the **+** button
2. Type the note name and press Enter
3. The note is created in the currently selected folder

## Moving notes and folders

Drag and drop notes and folders in the sidebar to reorganize them. Drop a note onto a folder to move it inside.

## Renaming

Right-click a note or folder in the sidebar and select **Rename**. The file is renamed on disk.

## Deleting

Right-click and select **Move to Trash**. Deleted notes are moved to a hidden `.quartztrash` folder in your vault (not permanently deleted). On macOS, you can access the trash from the sidebar.

## File compatibility

Since notes are standard Markdown files, you can:

- Edit them in any text editor (VS Code, Sublime, vim)
- Sync them with any cloud service (iCloud, Dropbox, Google Drive)
- Version control them with Git
- Process them with scripts or other tools

---

**Next:** [iCloud Sync](icloud-sync.md)
