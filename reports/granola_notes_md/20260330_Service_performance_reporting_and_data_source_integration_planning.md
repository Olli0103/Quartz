# Service performance reporting and data source integration planning

- Note ID: not_81uqYytkpimVgU
- Created: 2026-03-30T15:01:25.986000+02:00
- Updated: 2026-04-01T09:07:37.380000+02:00
- Note Date: 2026-03-30
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Team Updates & Personnel Changes

- Dominik received employment contract email, likely starting May 1st (next business day)
  - Will receive equipment from company
- New MacBook ordered with M-series chips now in catalog
  - Cost center assignment issue - Georg listed instead of Oliver
  - Need to coordinate with Kaiser about cost center correction

### Service Performance Reporting & Data Sources

- SPC service requests missing critical data in current brownfield approach
  - Rolf (Data Product Owner) confirmed greenfield rebuild by end Q2
  - New version will include assignment groups and component information
  - Will enable identification of ticket ownership and Cast organization mapping
- Current data product limitations
  - Cannot determine who worked on tickets
  - Missing organizational attribution
  - Lacks necessary attributes for meaningful reporting
- Service performance reporting requirements
  - Internal comprehensive view needed (all tickets, follow-ups, work volume)
  - Customer-facing reporting separate from internal metrics
  - Monthly PowerPoint generation via Claude automation planned

### Votorantin Project & Data Access

- Fernando requesting complete ticket data including body/history for AI analysis
  - Giancarlo and Matthäus collaborating (both speak Portuguese)
  - Data currently in ESX HANA Cloud from old system
- Amara working with Siva and Mark (AI consultants) on HANA consolidation
  - Moving to single central HANA to reduce costs
- Project framework established
  - Proof of concept in ePA super account
  - Secured interface for Votorantin customer number only
  - Maximum support provided with proper guardrails
- Customer health scoring system in development
  - Simple factor calculation (0.1 to 3.0+ scale)
  - Under 1.0 = not operational, 3.0+ = acceptable customer
  - Tracks onboarding phases and operational readiness

### Current Challenges

- Significant onboarding backlog with tickets on hold
- External delivery team performance issues in Rise environment
  - Aldi engagement delayed due to ECS system problems
  - Contract started January 1st but no systems available
- Multiple data sources now integrated
  1. Account master data
  2. ASM and ICP information
  3. Cloud data from BDC
  4. Additional integration requests incoming
- All data consolidating into ESX for future optimization

---

Chat with meeting transcript: [https://notes.granola.ai/t/bd638679-c820-4be1-85e0-803f1401ce7f](https://notes.granola.ai/t/bd638679-c820-4be1-85e0-803f1401ce7f)
