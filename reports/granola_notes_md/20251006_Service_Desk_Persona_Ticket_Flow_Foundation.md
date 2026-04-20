# Service Desk Persona / Ticket Flow Foundation

- Note ID: not_57hNVaAfVlY9pC
- Created: 2025-10-06T11:00:35.961000+02:00
- Updated: 2025-10-06T14:38:54.105000+02:00
- Note Date: 2025-10-06
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: Service Desk Persona / Ticket Flow Foundation
- Scheduled: 2025-10-06T11:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Team meetings

### Information

- Service Desk Persona/Ticket Flow Foundation meeting focused on aligning ticket routing and escalation processes for the new Foundation package
- Foundation package introduces shift from commercial service desk to L1 area for ticket routing
- Multiple entry channels available for customers:
  - SAP for Me case app
  - Cloud ALM API (successor to solution manager integration)
  - Service request app for assisted service requests
- Foundation package spans multiple delivery teams: monitoring, security, basis, performance, and data
- Current landscape uses mixed tooling: ESP, SPC, and ServiceNow depending on team and function
- First Foundation customer (AkroLima) contract started October 1st, but system setup still pending
- Majority of Foundation tickets expected to be service requests rather than cases
- Service desk currently lacks capability to monitor SPC tickets, which is required for Foundation support

### Decision

- Package-specific kickoff required for Foundation customers to explain proper ticket channels
- Service requests should be primary channel for Foundation reactive work
- Incidents mostly covered by ECS/RISE, customers should use that route
- Need separate service request templates for each functional area (monitoring, security, performance, etc.)
- Cannot implement full service desk monitoring capabilities within 2-3 weeks timeframe

### Action

- Oliver to schedule meeting with Manish and Jay to review escalation model (October 20th at 10:00)
- Kathrin and Jana to connect with ECS escalation intake team to understand SPC ticket monitoring processes
- Stefan to create generic service request templates for each Foundation functional area (monitoring, security, performance)
- Team to prepare specific questions for Manish regarding proposed escalation model before next meeting
- Oliver to coordinate with ASM for package-specific customer kickoffs
- Follow-up workshop scheduled for tomorrow to discuss contract onboarding and master data requirements

### Risk

- Service desk team not prepared for Foundation package launch - lacks training, system access, and procedures
- Multiple entry channels (ESP, SPC, ServiceNow) create complexity for ticket monitoring and routing
- No clear guidance for service desk on how to categorize and route Foundation tickets to appropriate teams
- Potential for customer confusion about proper ticket channels without clear communication
- Major incident process integration with ECS not yet defined for Foundation scope
- Service desk cannot currently monitor tickets across all required systems (ESP, SPC, ServiceNow)

---

Chat with meeting transcript: [https://notes.granola.ai/d/62a27d8d-9613-4a66-aef8-a758b8dfb7f5](https://notes.granola.ai/d/62a27d8d-9613-4a66-aef8-a758b8dfb7f5)
