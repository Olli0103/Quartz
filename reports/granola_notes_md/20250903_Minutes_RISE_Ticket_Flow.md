# Minutes: RISE Ticket Flow

- Note ID: not_Z28eNjNXQIENib
- Created: 2025-09-03T15:00:00.686000+02:00
- Updated: 2025-09-22T20:22:19.292000+02:00
- Note Date: 2025-09-03
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: Minutes: RISE Ticket Flow
- Scheduled: 2025-09-03T15:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Service Desk as Central Routing Hub

- Single entry point for all technical issues (incidents/alerts/cases)
- Service desk analyzes tickets and dispatches to correct L3 teams
- Enables L1/L2 consolidation across foundation package scope
  - Security monitoring, performance monitoring, data volume management
  - Customer incidents for basis and other technical areas
- Service desk maintains ownership throughout ticket lifecycle
  - Can escalate if forwarded tickets aren’t addressed
  - Single point of contact for customers vs current multi-queue confusion

### Two-Tool Architecture Design

- Cases route through ServiceNow
  - Customer uses SAP for Me or Cloud ALM API
  - Single component (XX-CAST or XX-AMS) for customer visibility
  - Service desk dispatches to monitoring, basis, security, performance teams
  - Can route to ECS/Product Support via existing components
- Service requests use SPC
  - Separate queues needed for monitoring, security, data management
  - Reuses existing AO process with scheduled execution model
  - No solution time SLAs - only scheduled delivery commitments

### ECS Integration Requirements

- Tickets from ECS maintain original priority (no re-prioritization)
- Service desk must comply with inherited cloud agreement SLAs
- Bidirectional routing capability needed
  - ECS tickets route to foundation teams via service desk
  - Foundation alerts can create tickets to ECS when needed
- Major incident management process alignment still required

### Implementation Timeline & Dependencies

- Component creation needed in ServiceNow/ESP
  - Quarterly component updates in SAP for Me
  - Q3/Q4 target for new components if requested now
- Service desk persona definition required
  - Discussion with Harsha/Catherine needed after internal alignment
  - Foundation workshop slot Tuesday for initial discussion
- AI routing and conversational interface
  - SAP project started July 2024 but unlikely before 2026
  - ServiceNow auto-response agents already deployed (1% of tickets)

### Next Steps

- Oliver: Finalize service desk persona description
- Oliver: Create ServiceNow/ESP components with master data team
- Oliver: Align with Katrin on fastest component creation approach
- Team: Present flow at Tuesday foundation workshop slot
- Oliver: Schedule discussion with Harsha/Catherine next week during workshop
- All: Develop measurement concept ensuring SLA compliance without manual overhead

---

Chat with meeting transcript: [https://notes.granola.ai/d/6c5afaa7-0a6a-4052-bfbe-8fafe92df78a](https://notes.granola.ai/d/6c5afaa7-0a6a-4052-bfbe-8fafe92df78a)
