# Service Performance Dashboard 

- Note ID: not_XYVk5iab5pPcu7
- Created: 2025-11-06T11:31:43.881000+01:00
- Updated: 2025-11-06T12:05:43.265000+01:00
- Note Date: 2025-11-06
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: Service Performance Dashboard 
- Scheduled: 2025-11-06T11:30:00+01:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Service Performance Dashboard Testing Feedback

- Issue tracking review from Tom, Oliver, and Andreas feedback
- Password authentication required each time - no single sign-on available for dev environment
- Top 5/10 customers by ACV analysis
  - Will align with QBR dashboard approach instead of separate implementation
  - Service performance pages to be consolidated with existing dashboards
  - Access control based on individual pages rather than separate dashboard

### Critical Data Issues Identified

- Customer vs package distinction needed
  - Current view shows number of customers only
  - Missing number of packages per customer (critical for adoption/consumption tracking)
  - Customer may have 2-3 packages for same service offering
  - Quantity data available in cloud reporting for PCE customers, unreliable for C2C/Atlas
- Technical problems requiring fixes:
  - Margin analysis shows negative values with single SKU
  - Volume consumption displays >100% (yearly + normal ticket-based stacked incorrectly)
  - Charts not adjusting when time period changed (showing 2024 data)
  - Filter inconsistencies between left panel and top selections
- Revenue analysis error messages appearing
- Deployment by ASPSA data unclear - copied from QBR dashboard without context

### Next Steps

- Oliver: Update Jira ticket with immediate fixes vs items requiring alignment
- Oliver: Provide timeline for completing action items before tomorrow’s meeting
- Separate 30-minute session needed for customer vs package data requirements
  - Include Tom for cloud adoption tracker expertise
  - Review raw data from report adoption for integrated solutions
- Create dedicated overview page with 5 key KPIs (will review PowerPoint slides shared earlier)
- Tomorrow 11:30 follow-up meeting to review documented action items and progress

---

Chat with meeting transcript: [https://notes.granola.ai/d/d8b408df-95cf-4542-b8df-3d737c3d5bd4](https://notes.granola.ai/d/d8b408df-95cf-4542-b8df-3d737c3d5bd4)
