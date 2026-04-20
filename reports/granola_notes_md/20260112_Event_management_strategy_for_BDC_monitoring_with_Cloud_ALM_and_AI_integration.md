# Event management strategy for BDC monitoring with Cloud ALM and AI integration

- Note ID: not_ocdv3EhQM9Wl8Y
- Created: 2026-01-12T08:33:02.215000+01:00
- Updated: 2026-01-14T10:05:50.174000+01:00
- Note Date: 2026-01-12
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Information

- The other participant was on a 6-day trip to Bali, visiting East, South, and West Valley areas
  - First time visiting Bali, described the architecture and ancient temples as magnificent
  - Streets lined with traditional elements on both sides of roads
  - Mix of modern attractions and heritage/tradition
- BDC (Business Data Cloud) service launched October 2025 and gaining traction
  - Currently has 4 paying customers: 1 in America, 1 in Canada, 2 in Australia
  - Coca-Cola reportedly signed as Q1 2026 deal
  - Previous discussions with Volkswagen (slipped to Q1), Deutsche Bahn status unclear
  - Recent partnership with Snowflake established
- Current BDC offering includes mix of BWS, SSC, Data Sphere, Data Breaks (public cloud) plus BW
  - Team built proprietary SAC dashboard for administration and monitoring
  - Includes Python script with AI inputs for job failure analysis and PDF reporting
  - Dashboard requires manual deployment for each customer requesting monitoring option
- Pune team monitoring support depends on customer contract structure
  - Available if customer has foundation package + BDC contract
  - Not available for BDC-only deals, forcing reliance on proprietary dashboard

### Decision

- Event management functionality will be developed for BDC offering
  - Will provide real-time monitoring of BW jobs, SSC/Data Sphere loads, data flows, data models, stories, and users
  - Current proprietary SAC dashboard will be decommissioned once event management is deployed
- AI functionality will be deployed on EPA (SAP’s SaaS landscape) using internal tenant
  - Provides consistent offering across all customers rather than two-tier service
  - Data segregation already available through existing EPA customer tenant structure
  - Can leverage existing Foundation customer data if applicable
- Cloud ALM will connect to customer environments while AI processing occurs on EPA tenant
  - Works for both private cloud (BW) and public cloud (SSC, Data Sphere) components
  - Can deploy Cloud ALM in customer subaccount on EPA if customer doesn’t have it set up

### Action

- Development team to prepare business case and skill set requirements document
  - Include architectural specifications and resource needs
  - Submit to Oliver for supplier management to source external development resources
- Schedule technical design meeting with Michael once business case is complete
  - Review EPA tenant requirements and customer isolation needs
  - Finalize architectural approach for event management integration

### Risk

- Development resources not available internally (team currently busy)
  - Mitigation: Source external supplier with appropriate skill set through vendor management
- Two-tier customer service risk if AI deployment varies by customer AI token availability
  - Mitigation: Standardized internal EPA deployment ensures consistent service level
- Manual dashboard deployment process not scalable for growing customer base
  - Mitigation: Event management automation will replace current manual process

---

Chat with meeting transcript: [https://notes.granola.ai/t/1e322e0b-c668-48f3-84d7-6899f6976f76](https://notes.granola.ai/t/1e322e0b-c668-48f3-84d7-6899f6976f76)
