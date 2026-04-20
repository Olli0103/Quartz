# ServiceNow ticket process alignment for Ariba support team

- Note ID: not_SEOR7ml3M0UQ5Z
- Created: 2026-03-05T14:05:21.323000+01:00
- Updated: 2026-03-05T14:59:54.775000+01:00
- Note Date: 2026-03-05
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

Ozzc

### ESP to ServiceNow Ticket Migration Process

- Ticket routing workflow confirmed

  - New tickets sent to partner → ESP → automatically forwarded to ServiceNow
  - Automatic process validation triggers immediate forwarding when contract found
  - Existing ServiceNow contracts remain unchanged, run independently
  - Only applies to new/renewal contracts, not legacy agreements

- Priority 1 ticket handling

  - P1 tickets forwarded directly to ServiceNow in “in process” status
  - Triage performed by current Ariba team within ServiceNow
  - Manual forwarding capability now functional after recent fixes

- Component mapping requirements

  - Ahmed and Lucas assigned to create component mapping
  - Single recognizable component structure needed
  - Key user concept remains unchanged from current process

### Solution Time Monitoring Challenges

- Current limitations identified

  - No SLA visibility in ServiceNow for customer-specific solution time agreements
  - ESP loses ticket visibility once forwarded to ServiceNow
  - No automatic replication of ticket updates back to ESP

- Proposed solutions discussed

  1. Manual monitoring approach
    - Ariba team creates dashboard reports in ServiceNow
    - Daily manual review for solution time tickets
    - Temporary workaround until automated solution available
  2. ESP-based tracking enhancement
    - Leverage existing exclude/include time settings in ESP contracts
    - Calculate solution time timestamps for monitoring
    - Requires technical implementation by Steffen’s team
  3. ServiceNow project integration
    - Submit requirements to René’s ServiceNow project
    - February deadline already passed for end-of-year delivery
    - Standard SLA profiles available in MVP, but no customer-specific options

### Action Items and Next Steps

- Natalia to define case categorization process for ServiceNow

  - Determine incident vs. change classification workflow
  - Coordinate with delivery team on categorization standards

- Solution time agreement verification needed

  - Review Ariba contract terms with ServiceNow requirements
  - Confirm alignment with existing Pharm package solution times
  - Validate customer-specific vs. standard SLA requirements

- Technical implementation planning

  - Begin mapping table development for component routing
  - Implement forwarding logic in ESP system
  - Coordinate with René on ServiceNow project requirements inclusion

---

Chat with meeting transcript: [https://notes.granola.ai/t/ea33f0ec-75a8-45b0-8cfc-6eeef8a54647](https://notes.granola.ai/t/ea33f0ec-75a8-45b0-8cfc-6eeef8a54647)
