# Quartz Specifications

This directory contains feature specifications following the PRD-driven workflow.

## Structure

```
docs/specs/
├── README.md           # This file
├── template.md         # Specification template
├── 001-editor.md       # Markdown editor specification
├── 002-sidebar.md      # Sidebar specification
├── 003-navigation.md   # Navigation specification
└── ...
```

## Specification Template

Each spec should include:
- Status (Draft | In Review | Approved | In Progress | Complete)
- Priority (P0 | P1 | P2)
- User stories
- Acceptance criteria
- Technical design
- Accessibility requirements
- Platform considerations
- Test plan

## Usage

1. Create spec before implementation
2. Get approval before starting work
3. Update spec as understanding evolves
4. Reference spec in PR descriptions

## Creating a New Spec

```bash
# Use the slash command
/generate-spec <feature-name>
```

Or copy `template.md` and fill in the sections.
