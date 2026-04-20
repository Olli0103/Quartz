# Abstimmung HCSM AI

- Note ID: not_ppeSBSqjHxCJ4c
- Created: 2025-09-16T10:00:21.246000+02:00
- Updated: 2025-09-16T10:21:53.645000+02:00
- Note Date: 2025-09-16
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: Abstimmung HCSM AI
- Scheduled: 2025-09-16T10:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### CAS Service Overview & Current Setup

- Cloud Application Services (formerly AMS) provides subscription cloud services across solution areas
- Operating in ITSM mode with own components under XX-AMS
- Handle service requests, incident/problem/change management for customers
- Work on Business Client implementations (non-Triple Zero mandant)
- Currently using Solution Manager (legacy ticketing system) with custom AI capabilities
  - Own ticket summary functionality
  - Solution recommendations
  - Sentiment analysis
- \~650,000 tickets in BTP Vector Engine database for similarity analysis
- Moving to ServiceNow with Enterprise Cloud Services (ECS)

### Data Lake Integration Discussion

- HCSM Data Lake contains all product support components and ServiceNow ticket data
- Built 6-7 years ago specifically for AI-supported customer support
- Strict data protection compliance (GDPR, CNDP, Sovereign Cloud)
  - Customer data requires anonymization/pseudonymization
  - Multiple opt-out lists maintained
  - Legal review process for all use cases
- Current services integrated into ServiceNow:
  - Component prediction for customer inputs
  - Automated solution suggestions for known problems
  - Support engineer efficiency tools
- Question: Are XX-AMS component tickets already in the Data Lake?
  - Some concern XX components might be excluded as “special components”
  - Need to verify ticket coverage before proceeding

### Next Steps

- Oliver to send sample case numbers/ticket numbers with component details to Thomas
- Thomas will check internally if CAS tickets already exist in Data Lake
- If not present, investigate why they’re missing
- Future: Formal use case proposal if CAS wants to develop in HCSM environment
  - Requires detailed data usage description
  - Legal/privacy review process
  - Ethics compliance for AI applications

---

Chat with meeting transcript: [https://notes.granola.ai/d/237425dc-9ff8-4edf-bc43-5f1cc0fb0a2d](https://notes.granola.ai/d/237425dc-9ff8-4edf-bc43-5f1cc0fb0a2d)
