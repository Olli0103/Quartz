# CAS Joule Functions - Status

- Note ID: not_BFdDP0bHvxKIJS
- Created: 2025-09-16T13:01:25.267000+02:00
- Updated: 2025-09-22T20:22:19.291000+02:00
- Note Date: 2025-09-16
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: CAS Joule Functions - Status
- Scheduled: 2025-09-16T13:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Joule Setup Progress

- Successfully added Joule plugin to VS Code
  - Initial attempt in BTP subaccount failed with errors
  - VS Code documentation more detailed and comprehensive
  - Joule generator now available in palette
- Created test projects using available templates
  - Generated technical artifacts: scenarios, dialogue functions, slots
- Understanding emerging of Joule architecture
  - Scenarios define main functions (e.g., get open purchase orders)
  - Slots capture user parameters and filter conditions
  - Dialogue functions handle response logic and formatting

### Current Technical Challenges

- Deployment failing due to BTP connection errors
  - Trying to connect to dedicated Joule testing tenant
  - All BTP credentials entered but authentication issues persist
- No deployment achieved yet
  - Cannot test actual Joule conversations until resolved
  - Next step requires successful deployment for Hello World example

### Testing Environment Discussion

- Using separate S/4HANA playground account for Joule testing
  - Joule already enabled in test launchpad
  - Isolated environment for learning before production
- Oliver suggested using AMS FSC OData service for real-world testing
  - ESP contract data available through Omar (a.m.a.r.u.b.h.e)
  - Michael preferred starting with open OData services first
  - Avoid complexity of on-premise connections initially

### Documentation and Approach Confusion

- Multiple conflicting SAP approaches causing confusion
  - Joule Studio (in BTP Build)
  - Joule Editor
  - VS Code ID extensions
- External documentation better than internal SAP resources
- Colleague confirmed VS Code approach most practical
  - His project team avoided Joule Studio entirely
  - VS Code plugins more stable and usable

### Effort Investment and Next Steps

- 8 days effort over past month (2 days/week when no ABAP tasks)
- Planned progression:
  - Resolve connection issues and deploy Hello World
  - Test with open OData services
  - Move to real development environment testing
  - Eventually test in EPA production
- Timeline pressure: End of year decision point on technology adoption
- Monthly check-ins to track progress

### Action Items

- Maladia: Continue troubleshooting BTP connection errors for deployment
- Maladia: Share results once Hello World scenario working
- Oliver: Provide Omar’s contact details for ESP OData service access (if needed later)

---

Chat with meeting transcript: [https://notes.granola.ai/d/74556428-7521-4b87-a56b-4c7a2395fa79](https://notes.granola.ai/d/74556428-7521-4b87-a56b-4c7a2395fa79)
