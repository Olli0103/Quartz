# RISE Ticket Flow

- Note ID: not_IbPrCfnpE7ZZXG
- Created: 2025-08-19T09:00:02.686000+02:00
- Updated: 2025-09-22T20:22:20.312000+02:00
- Note Date: 2025-08-19
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: RISE Ticket Flow
- Scheduled: 2025-08-19T09:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Team meetings

### Information: RISE Ticket Flow and Team Alignment

- Ticket flow design for new foundational package follows premise of making process as easy as possible for customers
- Service request management and service catalog in ServiceNow will be deprecated - service request app will be permanent entry point
- Current service requests marked as chargeable; discussion needed on marking them as cloud application services
- Service requests will route through service request app to correct teams based on type (Basis, Security, Monitoring, Data)
- Each team (monitoring, security, data) needs dedicated SPC queue to avoid complicated forwarding from Roman’s team
- Case routing will use new XXX cars queue structure rather than old XX AMS queues
- Service desk colleagues require upskilling to identify ticket categories (monitoring, security, basis, data)
- AI categorization possibility exists for automatic ticket classification in ServiceNow
- Current alert handling:
  - Performance monitoring alerts in SPC
  - Application monitoring alerts in FROM (not SPC due to integration issues)
  - Mixed implementation across different monitoring types
- Future state: all alerts will move to ServiceNow, not SPC
- Monitoring team can create service requests but requires customer approval unless hack AS user is utilized

### Decision: Process and Tool Standardization

- Service request app confirmed as single entry point for service requests (not ServiceNow service catalog)
- Each functional team will maintain both ServiceNow component and SPC component
  - ServiceNow components primarily for alerts and incidents
  - SPC components for internal tickets, service requests, and automation tasks
- Service desk will handle ticket categorization and routing rather than automated identifier-based dispatch
- Manual correlation preferred over automated alert correlation due to technical limitations and reliability issues

### Action: Implementation Planning and Stakeholder Alignment

- Oliver to verify ticket flow design with Manish and Jay before proceeding
- Oliver to clarify hack AS user usage permissions with Maureen (process owner)
- Follow-up meeting to be scheduled with Manish for queue structure approval
- Document service desk skill requirements and categorization guidelines
- Define specific capabilities and scope for potential AI categorization feature with Jens
- Beautify current diagram before stakeholder review sessions

### Risk: Customer Experience and Process Gaps

- Customer confusion potential around where to open tickets (XX cars vs ECS vs product support)
- Service desk knowledge gaps in technical categorization across multiple domains
- Dependency on hack AS user approval process outside ECS organization control
- Missing correlation tracking between monitoring alerts and opened service requests
- Foundation package impact on current Rise R&R identifier-based routing system unclear
- Integration limitations for customers using cloud element integration (cases only, no service requests)

---

Chat with meeting transcript: [https://notes.granola.ai/d/4299638e-3d77-4b40-94f2-08d89ad765ea](https://notes.granola.ai/d/4299638e-3d77-4b40-94f2-08d89ad765ea)
