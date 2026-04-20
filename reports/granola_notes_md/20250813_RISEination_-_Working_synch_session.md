# RISEination - Working/synch session

- Note ID: not_eMCd0ezL6PafCG
- Created: 2025-08-13T11:01:07.072000+02:00
- Updated: 2025-09-22T20:22:20.313000+02:00
- Note Date: 2025-08-13
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: RISEination - Working/synch session
- Scheduled: 2025-08-13T11:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### System Monitoring Dashboard - Data Visibility Concerns

- Current dashboard shows very broad technical data extraction from CAS Efron
  - 400-500 metrics across multiple system parameters
  - Already aggregated for 3 instances but still overwhelming for customers
- Major concern: some parameters may be too critical/sensitive to show customers
  - Need to verify what should/shouldn’t be published to avoid SAP disadvantage
  - CAS Efron instance may contain attributes from 3+ years ago that aren’t customer-appropriate

### ECS Alignment Required

- Must get approval from ECS before showing infrastructure monitoring data
  - ECS owns the underlying platform, could object to threshold-based alerts
  - Risk of customer confusion between CAS monitoring vs ECS availability metrics
- Action plan for ECS consultation:
  - Create spreadsheet listing all parameters by category (Linux, database, etc.)
  - Email Andreas Klos and monitoring team contacts
  - Request review of what’s critical vs acceptable to show
- Reference points for validation:
  - ECS monitoring white paper (shows what they monitor publicly)
  - SAP for Me dashboard (shows customer-facing subset)

### Dashboard Aggregation Strategy

- Need additional aggregation layer above current technical view
  - Customers want simple green/yellow/red status indicators
  - Current granular metrics too technical for general consumption
- Proposed approach:
  - Split into application vs infrastructure monitoring
  - Create entry point tiles/cards for major categories
  - Maintain drill-down capability to detailed metrics
  - Avoid extensive text explanations (users don’t read them)

### Alert Integration Challenges

- Standard alert display needed alongside dashboard
- Current alerting process relies on email notifications, not dashboard status
- Key considerations:
  - Alerts don’t always correlate directly to tickets
  - Need selective filtering to show only relevant alerts
  - Must avoid showing alerts that stay “red” without clear resolution path
- API limitations: current version 4 APIs may be insufficient, version 5 has broader capabilities

### Next Steps

- Michael: Email ECS contacts (Andreas Klos, monitoring team) with parameter review request by tomorrow
- Abhijit: Continue health monitoring aggregation via existing email thread
- Holger: Lead performance monitoring aggregation discussion
- Rohan: Provide alert API examples and filtering criteria
- Team: Review SLA alignment document offline for next week’s discussion
- Timeline: ECS response expected within days, aggregation proposals by early October

---

Chat with meeting transcript: [https://notes.granola.ai/d/69520157-5486-4b93-9fbe-8ddb0f41126f](https://notes.granola.ai/d/69520157-5486-4b93-9fbe-8ddb0f41126f)
