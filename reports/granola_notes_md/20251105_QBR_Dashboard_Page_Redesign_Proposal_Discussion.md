# QBR Dashboard Page Redesign Proposal Discussion

- Note ID: not_3u9FREgA4wBkOq
- Created: 2025-11-05T13:01:32.834000+01:00
- Updated: 2026-03-03T14:53:54.641000+01:00
- Note Date: 2025-11-05
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: QBR Dashboard Page Redesign Proposal Discussion
- Scheduled: 2025-11-05T13:00:00+01:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Dashboard Consolidation Proposal

- Hemant presented proposal to merge duplicate dashboard pages sharing same data sources
- Current issue: same datasets (supply information, revenue, backlog) duplicated across multiple dashboards (QBRs, supply performance, delivery excellence)
- Examples of redundancy:
  - ECV/ACV analysis duplicated between pipeline and supply performance
  - Volume consumption replicated from delivery excellence
  - Financial analysis redundant across multiple dashboards
  - Supply analysis duplicated in volume and spend pages
- Proposed solution: maintain single page per data type, enhance with additional views as needed
- Access control through role-based page visibility rather than dashboard-level restrictions

### Technical Implementation & User Access

- Current SAC limitations prevent data-level access control - only page visibility can be managed
- Future data sphere implementation will enable granular data restrictions by role
- Two navigation options discussed:
  - Catalog approach - users only see authorized tiles
  - Navigation panel - users see all links but cannot access unauthorized content
- Catalog method preferred to avoid user confusion and access requests
- Wiki page integration suggested for easy dashboard access requests

### Timeline & Next Steps

- Team consensus: complete Wave 1 rollout before implementing consolidation changes
- Reasoning: avoid redundant work since data foundation/data products migration will require model changes anyway
- Immediate actions:
  - Working session with dashboard owners and builders to identify shared datasets
  - Alignment meeting on supply analysis vs volume/spend analysis differences
  - UAM redesign discussion after technical consolidation decisions
- No urgency on implementation - focus remains on completing current dashboard development and rollout

---

Chat with meeting transcript: [https://notes.granola.ai/d/06cfa482-12c5-4c98-83ec-f75d460d4df3](https://notes.granola.ai/d/06cfa482-12c5-4c98-83ec-f75d460d4df3)
