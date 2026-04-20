# CAS Delivery Platform /Services weekly

- Note ID: not_Dig0DAWm9kJhwU
- Created: 2025-08-07T10:00:01.607000+02:00
- Updated: 2025-09-22T20:22:20.315000+02:00
- Note Date: 2025-08-07
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: CAS Delivery Platform /Services weekly
- Scheduled: 2025-08-07T10:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Team meetings

### Ticket Counter Implementation for Benny

- Request to measure ticket back-and-forth frequency before first solution proposed
- Counting methodology discussion:
  - Count every status change between customer and consultant
  - Include: In Process → Customer Action → back to In Process
  - Each ticket minimum count of 1 (when received)
  - Example: t1 (received) → t2 (consultant takes) → t3 (customer reply) → t4 (solution proposed) = count of 4
- Implementation questions:
  - Whether to count internal steps (Product Support, On Hold)
  - Real-time vs. end-of-ticket calculation
  - Field naming: “Customer Actions Until First Solution Proposed”
- Next step: Oliver to email Benny for clarification on internal step counting

### AI Sentiment Analysis UI Integration

- Three AI-generated scores (1-5 scale) for each ticket:
  - General sentiment (positive/negative/critical)
  - Customer emotions (frustrated/disappointed)
  - Tone analysis (aggressive/neutral)
- UI placement strategy:
  - Location: Details section, under General Data or between Processing/General Data
  - Display: Three colored circles (red/yellow/green) with mouseover descriptions
  - Alternative: Info icons with expandable text
- Implementation approach:
  - Avoid adding more text fields to tickets
  - Make sentiment immediately visible to consultants
  - Include actionable recommendations per score

### Similar Tickets AI Search

- Feature to find 3-5 most similar tickets using vector search
- Implementation as new text type (like ticket summary)
- Triggered automatically when ticket updated
- Display format:
  - Similar to existing ticket summary functionality
  - Include clickable links to related tickets
  - Consider access permissions for cross-customer tickets
- Concerns about recurring tickets creating noise in results

### Weekly Customer Reports Cleanup

- Current issue: Error reports for customers without active contracts
- 48 customers currently in automated report generation
- Many likely have expired AMS contracts
- Steffen to provide customer list for review
- Plan to remove inactive customers from automatic generation
- Focus on customers who actually access/use the reports

### Outcome-Based Ticket Reporting

- New requirement to separate outcome-based tickets from standard counts
- Similar to existing Additional Service Order and Internal ticket categories
- Implementation in CRM UI and SAP consumption tile
- Timeline dependent on SAP’s PI scheduling

### Joule AI Assistant Extension Project

- Goal: Extend Joule to answer CAS-specific questions via API calls
- Technical approach:
  - Use Joule functions (not agents) to recognize CAS queries
  - YAML-based configuration for keyword matching
  - Call OData APIs in ABAP landscape for responses
- Example target: “How many CIIs were created yesterday?”
- Development environment: BTP EU12 sandbox with activated Joule
- Work allocation: 60% ABAP tasks, 40% Joule development
- Malali to start with GitHub tutorials and contact SAP Labs colleagues for guidance

### Next Steps

- Oliver: Email Benny about ticket counter internal step requirements
- Steffen: Extract customer list for weekly reports review
- Steffen: Check UI feasibility for sentiment analysis display options
- Malali: Begin Joule function tutorials and establish SAP Labs contacts
- Team: Follow up on outcome-based ticket separation implementation timeline

---

Chat with meeting transcript: [https://notes.granola.ai/d/6077edfe-ba12-4281-8505-007b794c4f29](https://notes.granola.ai/d/6077edfe-ba12-4281-8505-007b794c4f29)
