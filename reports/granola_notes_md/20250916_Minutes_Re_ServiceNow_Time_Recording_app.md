# Minutes: Re: ServiceNow Time Recording app

- Note ID: not_XYCDoWftngiDww
- Created: 2025-09-16T09:00:42.187000+02:00
- Updated: 2025-09-22T20:22:19.292000+02:00
- Note Date: 2025-09-16
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: Minutes: Re: ServiceNow Time Recording app
- Scheduled: 2025-09-16T09:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### ServiceNow Time Recording App Development Plan

- Project scope: 80 development days maximum (40 functional, 40 technical)
- RAP developer from Minghouse available from second October week
- Michael providing advisory support (\~30 minutes weekly)
- Current broken app exists but unusable due to bugs
  - Built by Georg originally, Amal attempted rebuild
  - Internal users use app, external users log directly in ESP

### Functional Role Assignment

- Need someone for business requirements gathering and stakeholder alignment
  - Estimated 2 days per week commitment
  - Must translate requirements for developers at attribute level
- Potential candidate: Colleague from team (needs discussion)
  - Oliver to discuss in tomorrow’s 1-on-1
  - If agreed, Tom and Michael will explain project setup
- Alternative: External consultant through Minghouse

### Technical Architecture Approach

- RAP-based solution confirmed as correct path
- System architecture framework to be provided upfront
  - Prevents developer creativity in naming conventions
  - Establishes clear boundaries and structure
- ServiceNow ticket integration required
  - Current approach: button-based launch from tickets
  - Mass entry capability needed for bulk time logging
- API access to ServiceNow tickets essential
  - ServiceNow data replication to ESX environment planned
  - Generic ticket interface needed for multiple use cases

### Service Request Strategy Discussion

- Current mixed approach: internal users via app, external via ESP
- Future consideration: migrate service requests from SPC to ServiceNow
  - Phase 2 implementation post-go-live
  - Debate over maintaining SPC vs ServiceNow service catalog
  - Foundation services to remain in SPC for automation capabilities
  - Need separate meeting to resolve service request routing strategy

### Next Steps

- Oliver: Discuss functional role with colleague in tomorrow’s 1-on-1
- Tom: Schedule architecture meeting with colleague if she agrees
- Mid-October: Joint kickoff meeting with RAP developer
- Tom: Provide system framework and 3 architecture slides before kickoff
- Oliver: Set up meeting for service request strategy discussion

---

Chat with meeting transcript: [https://notes.granola.ai/d/b7b4e863-8137-4e32-9732-55664eb9871a](https://notes.granola.ai/d/b7b4e863-8137-4e32-9732-55664eb9871a)
