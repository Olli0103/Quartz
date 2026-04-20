# Reporting and performance dashboard strategy for CAS cloud services

- Note ID: not_KMewZG5EDXCnht
- Created: 2025-11-28T11:04:16.881000+01:00
- Updated: 2025-11-28T11:43:21.887000+01:00
- Note Date: 2025-11-28
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Agrolimit Project Status

- Kickoff meeting completed day before yesterday
- Service execution kickoff now required
  - Service plan, KT plan, and setup preparation
  - Customer awareness activities pending
- Foundation work still fluid due to first-time implementation
  - More effort required initially for each case
  - Templates will streamline future customer onboarding

### Service Performance Dashboard Development

- ESP data extraction automation in progress
  - Stefan creating OData service for active packages
  - Contract cleanup completed to identify fixed vs custom packages
  - CAS package name field populated for custom contracts
- Adoption tracking logic:
  - Based on ticket presence in ADM components
  - Kickoff/onboarding tickets automatically created when contract status changes to “released”
- Consumption tracking (100% when all present):
  - Monitoring tickets
  - Security monitoring tickets
  - Performance tickets
  - Security patching tickets
- Next checkpoint in 2 weeks with initial CAS for Private Cloud data

### Customer Reporting Automation Strategy

- Two-tier reporting approach:
  - Management reporting (adoption/consumption via SAP)
  - Customer reporting (trimmed down template)
- Current manual process pain points:
  - Excel-based trend analysis for 6-month alert data
  - VBA automation for PowerPoint generation
  - Multiple data sources (ESP, F-Run, Cloud ALM)
- EOS contract SLA reporting handled separately by existing US reporting
- Michael’s POC for CAS Delivery Dashboard customer version in progress

### Next Steps

- Jay: Prepare trimmed down customer report template by next Thursday 14:30
- Jay: Create Excel mapping of data sources (manual vs automated)
- Oliver: Schedule meeting with Manish to discuss BPA developer assignment
- Team: Pursue Python/BPA agent development for report automation
  - 70% of tickets generated proactively by SAP services
  - Focus on preventing manual effort for every customer report

---

Chat with meeting transcript: [https://notes.granola.ai/t/18c50e38-3da3-4c5c-b14a-eb626e755986](https://notes.granola.ai/t/18c50e38-3da3-4c5c-b14a-eb626e755986)
