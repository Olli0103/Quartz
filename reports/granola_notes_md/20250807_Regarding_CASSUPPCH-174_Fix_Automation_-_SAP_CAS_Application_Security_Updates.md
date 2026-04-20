# Regarding CASSUPPCH-174 Fix Automation - SAP CAS Application Security Updates

- Note ID: not_Z8dqwNuPdmtotd
- Created: 2025-08-07T11:34:46.508000+02:00
- Updated: 2025-09-22T20:22:20.314000+02:00
- Note Date: 2025-08-07
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: Regarding CASSUPPCH-174 Fix Automation - SAP CAS Application Security Updates
- Scheduled: 2025-08-07T11:30:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Current Automation Ticket Status

- Agreed to close CASSUPPCH-174 ticket and open new one later
  - Scope not sufficiently defined yet
  - Team wants better aligned requirements before starting
- Will preserve existing information for future reference

### Master Data Automation Requirements

- Primary challenge: Creating/updating Excel file with customer system data
  - Manual effort every month for 280-290 recurring tickets
  - Many tickets contain incorrect or incomplete SID information
- Current data quality issues:
  - Old HEC/PCE contracts have poorest data quality
  - ASU packages generally have better maintained data
  - Standard service tickets often lack proper documentation
- Proposed automation approach:
  - Extract baseline data from ESP tickets
  - Use tickets as single source of truth initially
  - Return to ASMs/CDMs for validation where data appears incorrect
  - Focus on streamlining new ticket creation process (already improving for last 6 months)

### SAP Note Analysis Discussion

- Clarified Barrab’s AI service request is generic SAP note recommendation tool
  - Not specific to security notes
  - Developed for different use case
- Marlon’s audit reporting capability exists but serves different purpose
  - Can identify which security notes missing per customer system
  - More for compliance auditing than proactive analysis
- Solomon Dialer already provides some note analysis functionality
  - Can identify relevant notes for customer landscape
  - Many customers already using this feature

### Next Steps

- Lucas to provide three technical files to Sadip
  - ESP extract examples
  - Master data format requirements
  - Current monthly process documentation
- Vamshi to walk through detailed manual process in next call
- Team to define exact automation requirements for Sadip
- Continue parallel work on master data correction while building automation

---

Chat with meeting transcript: [https://notes.granola.ai/d/bf7d78ec-eb40-43f2-bc0c-13c79fabe39a](https://notes.granola.ai/d/bf7d78ec-eb40-43f2-bc0c-13c79fabe39a)
