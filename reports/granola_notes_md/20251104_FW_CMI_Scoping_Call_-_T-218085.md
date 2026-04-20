# FW: CMI Scoping Call - T-218085

- Note ID: not_wJR3BiREAnE7xY
- Created: 2025-11-04T16:32:29.730000+01:00
- Updated: 2025-11-04T17:00:54.400000+01:00
- Note Date: 2025-11-04
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: FW: CMI Scoping Call - T-218085
- Scheduled: 2025-11-04T16:30:00+01:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Information

- Visa application status update
  - Application submitted on Monday, received approval Friday night to Saturday
  - Processing time was 4-5 days, within expected timeframe
- Meeting reminder systems experiencing technical issues
  - No automatic reminders appearing for scheduled meetings
  - Had to manually check and remember meeting time
- Personnel updates shared
  - Isabel is currently sick
  - Natalia is available and present
- Customer operational dashboard capabilities explored
  - System allows filtering by removing “Customer Reporting relevant” flag to view all components
  - Dashboard performance remains slow, improvements still being reviewed
  - Regional breakdown functionality exists but may be difficult to locate
  - Data analysis feature provides detailed ticket-level visibility (280 tickets currently)
- Data integration project progress
  - Security concept submitted and now under review
  - First kickoff meeting completed with colleagues
  - Bruce has already set up initial framework
  - Development environment data availability estimated within one month
- Current ticket routing limitations identified
  - Only tickets sent to Product Support are replicated in ServiceNow
  - Not all SAP4Me tickets automatically create equivalent ServiceNow tickets
  - Customer zoom tickets and Solution Manager tickets not currently included in reporting
- Quality Management team requirements align with ASM needs
  - Same data basis required for quality management reporting
  - Multiple stakeholder groups need different view levels (regional, customer-specific, global)

### Decision

- Abandon current Qualtrics approach as it’s not feasible
- Pivot to leveraging existing Customer operational dashboard infrastructure
- Focus on enhancing current data product capabilities rather than building new solution
- Archive existing process documentation but keep accessible for potential future reference

### Action

- Oliver to create project plan and timeline
  - Target completion by Christmas (4-8 week timeframe)
  - Document requirements for different stakeholder groups (ASMs, DC Heads, Quality Management)
  - Define data basis, filtering capabilities, and ticket inclusion criteria
- Establish ESX environment data connection
  - Complete security review process
  - Implement data replication from BLC to ESX environment
  - Test functionality in development before production deployment
- Create comprehensive documentation
  - Define what data is included and excluded from reporting
  - Develop user instructions for different stakeholder groups
  - Document filtering and analysis capabilities

### Risk

- Limited ticket coverage may impact reporting value
  - Only capturing subset of total tickets (estimated 100 out of 3000 created tickets)
  - Tickets only included when customers confirm in SAP4Me
  - Missing customer zoom and Solution Manager tickets reduces overall visibility
- Technical implementation timeline uncertainty
  - Production deployment timeline dependent on development environment success
  - Multiple system integrations required (BLC, ESX, SAC)
- User adoption challenges
  - Dashboard complexity requires extensive documentation
  - Multiple user groups with different needs may require customized training

---

Chat with meeting transcript: [https://notes.granola.ai/d/766fc58b-cd1e-41e7-a7ed-531c7f4e7973](https://notes.granola.ai/d/766fc58b-cd1e-41e7-a7ed-531c7f4e7973)
