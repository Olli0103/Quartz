# Standard change approval process for CAS business clients

- Note ID: not_O2F2Qblw8paRQx
- Created: 2026-02-04T16:33:59.119000+01:00
- Updated: 2026-02-04T18:38:47.777000+01:00
- Note Date: 2026-02-04
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Service Request Overview

- Need for standard change approval service request in SPC system
- Covers CAS (Cost) business operations - holistic end-to-end basis service
- Minimum price point: €250k with successful uptake
- Allows proactive system changes without repeated customer approvals
  - Development and Q system modifications
  - Basic node fixes without restarts
  - Non-critical basis issue resolution

### Current Process vs. Proposed Solution

- Existing method: Email-based approvals for each change
  - Time-consuming ticket-by-ticket approval process
  - Currently only available for application security updates
- Proposed: Single service request for blanket approval
  - Customer raises request once, gets automatic closure
  - Creates legal document trail in system
  - Delivery consultants can see approval status instantly
  - Includes revoke option for customers

### Technical Implementation Details

- Platform: SPC system (not ServiceNow)
- Service request queue placement
- No connection to entitlement system currently
- Visibility concerns: All customers will see the service request
  - Need clear messaging about CAS package requirement
  - Risk of invalid requests from non-CAS customers
- Recommendation: Combine grant/revoke into single template
  - Dropdown for activity selection
  - Reduces template proliferation (approaching 200 total)

### Business Context & Volume

- Q4 results: 24 customer signings including Google, IBM
- Legal requirement for documented change approval
- System-level permissions (e.g., 10 clients under single system)
- Low volume expected but critical for operational efficiency

### Next Steps

- Initial approval granted by team
- Katana to present at next CDM/TSM circle meeting (following week)
- Oliver invited to support discussion if needed
- Davis to coordinate next level approvals with Katana

---

Chat with meeting transcript: [https://notes.granola.ai/t/a51bafa6-912c-476e-bc73-5d46743f53f7](https://notes.granola.ai/t/a51bafa6-912c-476e-bc73-5d46743f53f7)
