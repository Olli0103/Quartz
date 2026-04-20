# Application security updates and AI integration progress review with Oliver

- Note ID: not_4HPxu8tzyK70ED
- Created: 2026-02-24T09:36:06.616000+01:00
- Updated: 2026-02-24T10:02:22.569000+01:00
- Note Date: 2026-02-24
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Application Security Update (ASU) Automation

- New Fiori apps deployed to production for ESX team
  - Replaces manual Excel/SharePoint processes
  - Automates file generation for SBC procedures
  - Started using in February, team trained and providing feedback
- Key features implemented:
  - Monthly SAP notes upload capability
  - Historical data access and validation
  - Customer master contract verification
  - Automated ticket creation for active customers
  - Automation status validation (prerequisite checks)
- Development status: 95% complete
  - Minor improvements being addressed based on user feedback
  - Developed by speaker and Michael

### Joule Integration Progress

- Integrated 5 application monitoring services into Joule
  - Error monitoring, runtime errors, batch job errors
  - Created separate API services on top of existing CDS views
- Major limitation identified: response context size
  - API calls limited to top 20 records
  - Fails when requesting historical data (e.g., 2024 records)
  - Returns generic error messages instead of data
- Potential solutions being explored:
  - Vector embeddings in HANA Cloud for better data retrieval
  - Dynamic filtering based on user input (dates, business criteria)
  - Ticket raised with Joule team for context limit extension
- Performance optimizations implemented:
  - Dynamic query building with date filters
  - Keyword mapping to API fields

### Goal Setting for 2026

- Transition from 4 goals to maximum 3 goals this year
- Focus areas identified:
  1. AI development and enhancement
  2. People learning/development
- iCats dashboard integration planned
  - AI-powered functionalities for automation
  - Automatic service request/case creation
  - Data analytics for actionable insights
  - Intelligent forecasting capabilities
- Goal development approach:
  - Coordinate with Michael on technical goals
  - Focus on areas of direct influence
  - Consider adoption, proactiveness metrics

### Next Steps

- Follow up with Joule team on vector embedding feasibility for data retrieval scenarios
- Attend biweekly Joule consulting session this week
- Draft initial goals by March 6th (coordinate with Michael)
- Continue ASU app refinements based on user feedback
- Investigate HANA Cloud subscription requirements for vector DB

---

Chat with meeting transcript: [https://notes.granola.ai/t/f8e5e66f-883d-4a09-9006-ffa529431a1d](https://notes.granola.ai/t/f8e5e66f-883d-4a09-9006-ffa529431a1d)
