# FW: CAS for Cloud ERP - Ticket Components

- Note ID: not_dwTfnzaIjABlXR
- Created: 2025-09-17T14:34:08.585000+02:00
- Updated: 2025-09-17T14:52:35.045000+02:00
- Note Date: 2025-09-17
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: FW: CAS for Cloud ERP - Ticket Components
- Scheduled: 2025-09-17T14:30:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### ECS Process Migration Timeline

- Originally planned for end September, now officially moved to mid-November
- Current issue: Technology Services team completely forgotten in ServiceNow setup
- 140 SPC queues currently exist (100 incident, 30 service request queues)
- Major consolidation planned - many queues being eliminated or merged

### Current SPC Queue Strategy

- SPC queues won’t be migrated as-is for Technology Services team
- Meeting with Robert Geiler needed to discuss new SPC requirements
- Three new components needed:
  - Monitoring
  - Security
  - Data
- Current “Hack Enhanced Managed Services” component to be renamed
  - Proposed: “Private Cloud Technical Operations” or “Technical Service Requests”

### ServiceNow Component Structure

- Foundation ticket flow: Customer → SAP/API → Cases → Service components
- PCO Ops (Private Cloud Operations) replaces old HSTOPA queue
- Technology Services assigned to PCO Ops component with multiple assignment groups:
  - Standard assignment group (external partner work)
  - EU Delivery (EU-specific assignments)
  - L3 (special customers, internal subcontractor)

### Incident vs Service Request Handling

- Incidents cannot remain in SPC - must migrate to ServiceNow
- Service requests can continue via SPC temporarily
- Alert processing concerns: alerts land via event management in ServiceNow
  - Create incidents automatically
  - Require proper component assignment and closure workflow
- ESP route avoided for ECS incidents due to technical complications

### Next Steps

- Schedule meeting with Robert Geiler to finalize SPC requirements and component setup
- Clarify assignment group management responsibilities (likely ServiceNow EU team or similar)
- Coordinate with colleagues on missing ServiceNow configuration before November deadline

---

Chat with meeting transcript: [https://notes.granola.ai/d/bb281948-c102-410e-bcc2-f30d99ffd60d](https://notes.granola.ai/d/bb281948-c102-410e-bcc2-f30d99ffd60d)
