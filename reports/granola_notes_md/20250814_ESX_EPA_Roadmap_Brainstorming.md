# ESX/EPA Roadmap / Brainstorming

- Note ID: not_rN78K5axq24zFJ
- Created: 2025-08-14T15:00:33.452000+02:00
- Updated: 2025-09-22T20:22:20.313000+02:00
- Note Date: 2025-08-14
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: ESX/EPA Roadmap / Brainstorming
- Scheduled: 2025-08-14T15:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Platform Architecture Overview

- ESX (internal platform) and EPA (customer-facing SaaS platform)
  - ESX: Strict internal use for reporting and tooling, cross-customer data
  - EPA: Customer-facing for diverse scenarios, connected end-to-end with ESX
- CAS Data Foundation serves as central data hub
  - Bidirectional data flow: inbound from FRUN and outbound to EPA
  - Manual enrichment for security notes categorization
  - APIs for external consumption (Abidjet experimenting with AI integration)

### Security Automation Initiative

- Current manual processes unsustainable with scale
  - Teams Chat as primary work tool for security partners
  - Manual security analysis despite CSA availability
  - Excel-based error log processing via email
- Three planned Fiori apps for ESX platform:
  - Security notes loading and enrichment from SAP For Me
  - SPC procedure input file generation (Customer ID, System ID, Note Number)
  - Central error register for uploaded Excel tables with filtering capabilities
- Target: First app live by October 1st for dashboard display

### Technical Integration Challenges

- FRUN security concept needs verification for ESX connection
- BTP ABAP Cloud cannot connect to CAM currently
  - Stefan Jakob (CAM Product Owner) investigating with Steam Punk colleagues
  - Previous information suggested no adapter available
- CSA integration potential for automated note recommendations
  - Could eliminate manual note discovery process
  - API availability needs investigation

### Development Standards and Tooling

- All new apps must be ABAP Cloud compliant
  - Enterprise-ready development only
  - ESX as consolidation platform for standalone tools
- Jira ticketing mandatory for all transports
  - Labels and delivery dates needed for change control
  - Q4 delivery target for current backlog items
- Migration from CAS Launchpad to ESX BWZ Launchpad required

### Resource Allocation Concerns

- Estimated 400-500 person-days annually across platforms
  - Malati: 180 days/year, Jessie: additional third, Jean Carlos: partial contribution
- Risk of management questioning resource intensity
  - Services heavily manual despite years of automation discussions
  - Foundation work necessary but creates temporary overhead
- New Pass Service rollout provides opportunity for process electrification

---

Chat with meeting transcript: [https://notes.granola.ai/d/8f234db9-3516-4ea1-a020-5485a1fd3dea](https://notes.granola.ai/d/8f234db9-3516-4ea1-a020-5485a1fd3dea)
