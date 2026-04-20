# Database table growth and performance tracking strategy with Michael and Walter

- Note ID: not_41XKbHx2OXzJy6
- Created: 2025-08-22T10:03:19.025000+02:00
- Updated: 2025-09-22T20:22:20.311000+02:00
- Note Date: 2025-08-22
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### API Integration Requirements

- Need table growth data from EWA system for database housekeeping
- Focus on technical objects only, not business-critical tables
  - Filter by application components (BC, Cross Application, TA)
  - Customer gets complete overview but scope limited to technical tables
- Requirements include:
  - Table size data
  - Number of entries
  - Existing partitioning information
- Performance metrics already available through existing monitoring

### Data Access & Master Tables

- Master table lookup can be handled internally on BTP platform
  - Map tables to corresponding components
  - Only need raw table data from Walter’s team
- Table specifications readable from MCS Tables
- Data content access restricted (privacy compliance)
- Follow-up analysis via TANA for detailed data distribution

### Platform Development Process

- Michael will provide API template from new product manager
  - Template replaces previous Susanne workflow
  - Need written requirements documentation
- Development timeline: normally weeks, currently delayed
  - Two developers being reassigned to other projects
  - Timeline needs internal review

### Additional Use Case - Automated Ticketing

- Separate API request for EWA alert-based ticket creation
- Proactive ticket generation for fully managed customers
  - Performance issues, missing security notes, etc.
  - Alert categorization already mapped to components
- Integration with ServiceNow/HCSM pending API access
- Will create separate documentation rather than combining requests

### Next Steps

- Michael: Send API template for requirements documentation
- Oliver: Fill out template with detailed specifications
- Oliver: Create separate documentation for automated ticketing use case
- Walter: Research NSE cache performance metrics availability

---

Chat with meeting transcript: [https://notes.granola.ai/d/67e8813f-2f62-41d1-899b-310d2f66260f](https://notes.granola.ai/d/67e8813f-2f62-41d1-899b-310d2f66260f)
