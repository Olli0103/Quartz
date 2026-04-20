# ServiceNow integration for Cas4Ariba ticket routing process

- Note ID: not_huxYzwPmSn0LnG
- Created: 2026-02-24T15:05:21.951000+01:00
- Updated: 2026-02-25T08:52:35.727000+01:00
- Note Date: 2026-02-24
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Cast for Ariba ServiceNow Integration Overview

- Technical feasibility confirmed for Cast for Ariba using ServiceNow
- Contract master data stored in ESP, tickets replicated to ServiceNow for processing
- ESP acts as gatekeeper for contract validation, then routes to ServiceNow components
- Outstanding question from Sundar about mandatory ESP contract storage requirements

### Automated Contract Validation Process

- ESP automatically validates customer entitlement when tickets arrive
- System checks customer master data and component access rights
- Key user validation performed automatically
  - Only authorized users can create tickets
  - End users blocked from ticket creation
  - System sends rejection emails for unauthorized attempts
- Manual contract check only triggered if system uncertain about mapping
- Once validated, tickets marked as “sent to partner” in ESP

### Ticket Routing and Team Responsibilities

- ServiceNow receives tickets directly after ESP validation
- No ticket replication back to ESP once forwarded
- Triage team picks up tickets in ServiceNow for assignment
- Service desk no longer dispatches tickets to Cast for Ariba team
- SLA monitoring, reporting, and triage handled by Cast for Ariba team
- Need to align on reporting structure with country teams

### P1 Ticket Handling Process

- P1 tickets require 20-minute initial response time (IRT)
- Replication causes 5-6 minute delay for automatic processing
- Proposed P1 process:
  - Service desk provides initial response within IRT window
  - Manual forwarding to ServiceNow for P1 cases
  - P2-P4 tickets processed automatically
- Need discussion with Katrin/Yana on P1 process details

### Component Selection and Customer Experience

- Single component approach: XXAMS ARI for all Cast for Ariba tickets
- Customer selects component in final step of SAP for Me ticket creation
- Triage team routes to appropriate subcomponents after intake
- Avoids customer confusion with multiple component options
- Based on PSEE experience where wrong component selection caused routing issues

### Next Steps

- Oliver: Create change request for ESP support team (high priority)
- Oliver: Discuss P1 process with Katrin/Yana
- Oliver: Provide ETA for automatic forwarding development by Thursday
- Team: Decide on Cast for Ariba reporting ownership (internal vs. ESP)
- Manual forwarding available as backup if automation not ready for first customer

---

Chat with meeting transcript: [https://notes.granola.ai/t/a196f78c-ba9e-4df5-9687-d761b948f7a5](https://notes.granola.ai/t/a196f78c-ba9e-4df5-9687-d761b948f7a5)
