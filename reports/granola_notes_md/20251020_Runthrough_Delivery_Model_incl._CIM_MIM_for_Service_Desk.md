# Runthrough Delivery Model incl. CIM/MIM for Service Desk

- Note ID: not_zgmaqN9r2RkqJI
- Created: 2025-10-20T10:03:07.703000+02:00
- Updated: 2025-10-20T16:42:47.496000+02:00
- Note Date: 2025-10-20
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: Runthrough Delivery Model incl. CIM/MIM for Service Desk
- Scheduled: 2025-10-20T10:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Information

- Meeting focused on delivery model runthrough including Critical Incident Management (CIM) and Major Incident Management (MIM) for Service Desk
- Pune workshop scheduled for November 11-13, with participants including Abhijit, Catherine, Ali, and local Pune team members
  - Service desk process owner should participate due to ticket routing requirements
  - Extended to three days instead of two for better progress and results
  - Visa preparation and travel logistics being coordinated
- Current ticket flow structure established:
  - Service requests route through SPC (Service Provider Cockpit)
  - Incidents come via ECS (will move to ServiceNow by December 6) and XXAMS OPS component
  - 95% of incidents are RISE incidents going to ECS
  - Limited CAS-specific incidents expected (three-digit numbers over three years)
- Three-tool approach complexity identified:
  - ECS incidents forwarded in ServiceNow
  - ESP incidents
  - SPC service requests
- SPC monitoring currently handled by escalation intake team under Nick Baumann
  - Need to determine if service desk can take over this responsibility

### Decision

- Workshop dates confirmed: November 11-13 in Pune (three full working days)
- Maintain current customer communication: single entry point via XXAMS OPS component
- Service requests will continue using SPC, incidents through ESP/ServiceNow
- Critical incident management process will follow standard CAS procedures with service desk involvement
- Routing rules to be created for different delivery teams (OPS monitoring, security, basis, performance, data management)

### Action

- Oliver to provide routing rules specifications this week for service desk ticket assignment
- Schedule alignment meeting with Nick Baumann’s team (Abhijit, Oliver, Prajosh, Jana, Catherine, and Nick)
  - Address escalation handling and MIM process integration
  - Establish collaboration model between ECS and CAS teams
  - Review dashboard requirements and tool adjustments
- Natalia to lead service desk readiness project kickoff Wednesday
  - Define work packages for tooling, training, and engagement
  - Include Abhijit and Holger in project scope
- Travel coordination:
  - Reach out to Vaishali for visa letters
  - Vinaya approval required for travel
  - Mumbai flight option to be explored
- Abhijit to share presentation slides as baseline for future discussions

### Risk

- Service desk readiness timeline pressure with first customer delivery November 14
- ECS team may discontinue current support without proper handover process established
- Three-tool complexity could create dispatching chaos without detailed service desk instructions
- Time recording solution needed for incidents forwarded to Roman’s team under foundation contract
- Potential gaps in critical incident management handover between ECS and CAS teams
- Tool routing limitations between ESP and ServiceNow require technical validation
- Automated monitoring alerts creating customer-facing incidents may increase ticket volume unpredictably

---

Chat with meeting transcript: [https://notes.granola.ai/d/5ee77933-c490-4121-8a7b-c1e9d99faf6a](https://notes.granola.ai/d/5ee77933-c490-4121-8a7b-c1e9d99faf6a)
