# Recurring service ticket implementation strategy with Dirk

- Note ID: not_Z2fW6Pqj8PdhOF
- Created: 2026-02-27T10:30:23.518000+01:00
- Updated: 2026-02-27T14:00:04.854000+01:00
- Note Date: 2026-02-27
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Current System Architecture Issues

- Portfolio restructured end of last year into single End-to-End service
  - Performance monitoring consolidated
  - Monthly monitoring tickets per customer with detailed work logs
  - Various other recurring tickets added
- Roman now working across three tools (suboptimal):
  - Performance Management (previously no recurring tickets, only gym work)
  - SPC for main operations
  - ECS via ServiceNow for incident handling
  - ESP work also required

### Proposed Solution: Recurring Tickets in SPC

- Goal: Relieve ticket bot and Roman by moving recurring tickets to SPC
- Technical approach discussed:
  - Service definitions with recurrence capability
  - Customer purchases service once → generates recurring execution
  - Example: DBBC check runs every 30 days (productive systems), 90 days (non-productive)
- Implementation options explored:
  1. Manual recurrence creation per customer ticket
  2. Central recurrence that can be reused
  3. Automatic ticket generation via service execution
- Current limitation: SPC cannot create customer service requests manually
  - Only accepts tickets from ServiceNow and SAP for me interfaces

### Next Steps

- Heiko Braumann consultation needed
  - Determine if SAP for me can generate recurring tickets automatically
  - Explore scheduled task functionality for monthly ticket creation
- Alternative ServiceNow approach
  - Investigate service request functionality with scheduled tasks
  - Check if customer-facing request items can auto-generate SPC tickets
  - Contact René for service request management capabilities
- Preference: Individual monthly tickets rather than single ongoing ticket
  - Better measurement and tracking capabilities
  - Easier routing and component-specific handling

---

Chat with meeting transcript: [https://notes.granola.ai/t/723f1c21-073c-482d-bcc4-b7bf752abe68](https://notes.granola.ai/t/723f1c21-073c-482d-bcc4-b7bf752abe68)
