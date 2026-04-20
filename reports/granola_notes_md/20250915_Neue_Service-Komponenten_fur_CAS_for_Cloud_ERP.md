# Neue Service-Komponenten für CAS for Cloud ERP

- Note ID: not_ahDg8Znse8bqQj
- Created: 2025-09-15T15:30:02.780000+02:00
- Updated: 2025-09-22T20:22:19.292000+02:00
- Note Date: 2025-09-15
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: Neue Service-Komponenten für CAS for Cloud ERP
- Scheduled: 2025-09-15T15:30:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### New Service Component Structure for CAS Cloud ERP

- Foundation Service requires multiple delivery teams behind single customer-facing component
- Customer interaction through XXAMS-OPS component (similar to existing HACK EMS model)
- Manual dispatching to backend teams initially
  - PC (basis operations)
  - MUCC (monitoring)
  - Security teams
  - Data management
  - Performance management
- AI-assisted routing planned for future automation

### Component Architecture & Dispatching

- Single SAP component (XXAMS-OPS) maps to multiple customer-specific components
- Backend components needed:
  - PC (basis)
  - Security
  - Data management
  - Performance
  - Monitoring
- Naming convention: OPS prefix to identify Foundation Package services
- Manual ticket routing initially via service desk analysis
- Leverages existing Application Management logic for service requests

### Implementation Requirements

- Request new XXAMS-OPS component creation
- Most traffic will be service requests (automatic routing)
- Incidents historically low volume (\~118 over 3 years for AO)
- Contract mapping remains straightforward with customer-specific components
- SLA configuration needed for new components

### Next Steps

- Foundation planning meeting Wednesday with Kathrin and Harscher
- Detailed service case analysis needed for each delivery team
- Component creation request through ESP team (Ella, Gabi)
- ServiceNow tool impacts assessment required

---

Chat with meeting transcript: [https://notes.granola.ai/d/f679700f-7681-4b22-9b91-c8541b0932f5](https://notes.granola.ai/d/f679700f-7681-4b22-9b91-c8541b0932f5)
