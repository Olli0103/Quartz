# Recurring service tickets workflow optimization for ServiceNow and SPC

- Note ID: not_6FVEufxCLku0Ls
- Created: 2026-03-04T09:01:01.947000+01:00
- Updated: 2026-03-04T09:44:25.709000+01:00
- Note Date: 2026-03-04
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Recurring Ticket Solution Discussion

- Current problem: Recurring tickets for cloud ERP components stuck in ESP system
- Two potential approaches explored:
  - Move recurring tickets to PC component in ServiceNow
  - Use Service Request functionality for scheduling
- Atlas scheduling functionality available since 2021 but only for Atlas customers
  - EMEA PC package now included in Atlas
  - Could work for PTO customers specifically
- ServiceNow scheduling feature expected end of year but uncertain timeline
  - Stefan will follow up on concrete roadmap dates

### Technical Implementation Challenges

- J-S and Security teams not in ServiceNow, only have ESP access
  - Creates chicken-and-egg problem with tool migration
  - Teams reluctant to move to SPC without recurring functionality
- API limitations discussed with Heiko:
  - No simple API exists for Service Request creation
  - Would require understanding catalog logic, parameters, scheduling
  - Multiple projects exploring similar needs but nothing concrete
  - Browser automation not scalable or reliable solution

### Alternative Approaches Considered

- AI bot to create monthly tickets via Service Request app
  - Would need predefined templates in catalog
  - Could generate tickets that land in SPC
- External system integration possibilities
  - Enterprise platform could potentially trigger requests
  - Requires proper API development and planning
- Heiko emphasized need for:
  - Proper backlog item creation
  - Coordination with service plan owners
  - Customer communication strategy for scheduled activities

### Next Steps

- Stefan: Get updated timeline for ServiceNow recurring functionality
- Oliver: Consider reaching out to service plan component owners
- Team: Evaluate simplified approach using existing PC/KS components for immediate needs

---

Chat with meeting transcript: [https://notes.granola.ai/t/e4b12dba-e793-4f8b-8e59-e49c3c323b1e](https://notes.granola.ai/t/e4b12dba-e793-4f8b-8e59-e49c3c323b1e)
