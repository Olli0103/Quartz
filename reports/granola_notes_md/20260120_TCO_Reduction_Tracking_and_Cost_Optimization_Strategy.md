# TCO Reduction Tracking and Cost Optimization Strategy

- Note ID: not_vghyWX0Wf9nVMl
- Created: 2026-01-20T14:07:18.950000+01:00
- Updated: 2026-01-20T14:47:37.612000+01:00
- Note Date: 2026-01-20
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Current Automation Impact

- Application security updates digitalization
  - Reduced manual efforts by 60% (previous SharePoint-based process)
  - Moved from manual file preparation to automated ESX apps
  - Vamsi confirmed 50-60% reduction in monthly delivery efforts
  - Need specific hourly numbers for TCO calculations

### Scattered Data Collection Problem

- Current tracking systems fragmented across multiple platforms:
  - IT workman sheet with TCO reduction field
  - Jira tickets for automation items
  - Various Excel sheets and SharePoint lists
- 2025 automation savings exceeded €8 million for SPC procedures
- Need unified system to track ESP, AI, platform reporting, automation efforts

### Proposed Solution Approach

- Create master Excel sheet as starting point
  - Power BI dashboards on top for visualization
  - API integration where possible (SPC has available APIs)
  - Manual maintenance required for BPA and other automations
- Data collection strategy:
  1. SPC automations - automatic via cloud reporting APIs
  2. AI use cases - ESX logging already captures executions
  3. ESP enhancements - manual tracking only
  4. Apps digitization - manual estimation required

### Cost Tracking Requirements

- Include infrastructure costs alongside TCO reductions
  - ESX, EPA, ESP, and FM costs per month
  - 2025 was first complete year with EPA and ESX
- Cost per customer must decrease with scaling
  - Original BIF business case assumed €50-90 per small customer
  - Target: under €100 per month, maximum €1,200 annually
- AI and HANA instances driving cost concerns
  - Single HANA instance with AI core can cost €500-1,000/month
  - Need quarterly cost verification checkpoints

### Next Steps

- Oliver: Create master Excel sheet with historical data from last year minimum
- Michael: Explore API options for BPA automation data collection
- Michael: Provide January cost analysis breakdown (ESX, EPA infrastructure)
- Team: Maintain regular update cycle (suggested: every Phoenix meeting)

---

Chat with meeting transcript: [https://notes.granola.ai/t/2862e693-3327-435d-b606-3ce6311473dd](https://notes.granola.ai/t/2862e693-3327-435d-b606-3ce6311473dd)
