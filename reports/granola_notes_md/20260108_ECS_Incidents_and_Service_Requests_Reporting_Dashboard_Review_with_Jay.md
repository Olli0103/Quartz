# ECS Incidents and Service Requests Reporting Dashboard Review with Jay

- Note ID: not_T2SyQdSHq05iFB
- Created: 2026-01-08T13:02:56.669000+01:00
- Updated: 2026-01-14T10:08:38.345000+01:00
- Note Date: 2026-01-08
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Jay’s ECS Integration Requirements

- Wants ECS incidents and service requests added to Castle Delivery Dashboard
- Additional filtering capabilities requested:
  - Product-based filtering
  - Customer vs. internal ticket creation tracking
  - Proactive tagging for incidents
- Current reasoning: Cloud API services must be viewed in ECS context due to handoffs

### Technical Feasibility Assessment

- ECS incidents: Available via ServiceNow data products
  - Would require mirroring into ESX environment
  - BDC interface integration needed
- ECS service requests: Remain in SPC system
  - Additional SPC integration required
  - Current BDC work still months from production-ready
- Product filtering: Not possible without ESB data availability

### Strategic Concerns with ECS Integration

- Scope mismatch: Roman’s team handles \~50 of 1000+ ECS tickets per major customer
- Support burden risks:
  - Customer questions on ECS tickets outside our responsibility
  - Data inconsistency issues between systems
  - ASM fielding non-contractual support requests
- Creates “Pandora’s box” for ECS reporting where we have no operational involvement

### Alternative Approach Recommended

- Delay implementation until March-April 2026
- Focus on entitlement management integration instead
  - Provides access to SAP reporting infrastructure
  - Enables Cloud ALM for Services integration
  - Offers unified service reporting across silos
- Service and Support Data Hub discussions ongoing with Raquel and Mannisch

### Organizational Restructuring Impact

- New structure announced with minimal preparation
- Sanjay Kukhari accepted position 24 hours before announcement
- Multiple reporting changes affecting PE, consulting teams
- Foundation portfolio mysteriously absent from new org chart
- Delivery excellence vs. delivery office separation unclear

### Current Priorities

- Postpone ECS integration requests until Q2 2026
- Tom to investigate SPC data product availability
- Monitor entitlement management progress for unified reporting solution
- Assess organizational stability before major architectural decisions

---

Chat with meeting transcript: [https://notes.granola.ai/t/8dd39ee2-7dab-44e1-b663-9a9a05409152](https://notes.granola.ai/t/8dd39ee2-7dab-44e1-b663-9a9a05409152)
