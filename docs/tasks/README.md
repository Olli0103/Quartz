# Quartz Tasks

This directory contains task breakdowns for feature implementation.

## Structure

```
docs/tasks/
├── README.md              # This file
├── editor-tasks.md        # Editor implementation tasks
├── sidebar-tasks.md       # Sidebar implementation tasks
└── ...
```

## Task Format

Each task file tracks:
- Feature spec reference
- Progress summary
- Step-by-step tasks with subtasks
- Implementation notes
- Changes log

## Usage

1. Create tasks from spec: `/generate-tasks <feature-name>`
2. Work through tasks in order
3. Mark completed as you go
4. Document learnings in notes

## Task States

- `[ ]` Not started
- `[~]` In progress
- `[x]` Completed
- `[-]` Blocked

## Example

```markdown
### Step 1: Implement data model
- [x] Create FileNode struct
- [x] Add Identifiable conformance
- [ ] Add Transferable conformance
**Notes**: Used URL.absoluteString as stable ID
```
