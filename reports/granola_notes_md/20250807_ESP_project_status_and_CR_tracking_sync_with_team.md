# ESP project status and CR tracking sync with team

- Note ID: not_l8H8RkXUWO2B47
- Created: 2025-08-07T08:10:50.495000+02:00
- Updated: 2025-09-22T20:22:20.315000+02:00
- Note Date: 2025-08-07
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Testing Scope & Stakeholder Involvement

- Testing scope depends on change magnitude
  - Smaller adjustments: team can test independently
  - Larger changes require multiple stakeholders:
    - Delivery team for cast delivery dashboard
    - ASMs for cast delivery dashboard testing
    - Master colleagues for adoption report testing
    - Different stakeholders per affected app
- Test cases will be added for all changes

### CR140 Progress Update

- First dashboard nearing completion, expected live in August
- Initial scope significantly underestimated
  - Originally planned: 1 additional data source
  - Actual requirement: 13 different Excel items for complete database coverage
- Create customer delivery app: Michael finishing initial version in Q3

### ESP Enhancements

- Cast delivery dashboard monthly ticket accumulation view
  - Cannot currently show weighted tickets
  - Björk implementing changes for farm reframing project
  - Will proceed with remaining CR changes after completion
- AI enhancements: push shop now running in ESP
  - Need to define data display format in ESP
  - Implementation can start once display requirements finalized
- Ticket report in bucket (CR146)
  - Implementation started with parallel performance improvements
  - Question: should this appear in SAP for me?
    - Currently only in ESP report, not transferred to RSA
    - Limited customer usage (Rotorantim, Fraunhofer)
    - May recalculate total ticket numbers as first step

### Service Integration Updates

- ESP service now integration (CR150)
  - Item 1: ready
  - Item 2: in process
  - Item 3: requires discussion
- Alignment meeting scheduled for afternoon

### Back & Forth Counter Request

- New requirement from Winnie for report
- Currently have “number of solution proposed” metric
- Need additional counter for customer action frequency
- Counts ticket iterations: received → in process → customer action → in process
- Will discuss implementation location and requirements with Catherine

### Replication Issues

- Ongoing network vs W7 system inconsistency debate
- Stefan identifies W7 system issue, not network
- Root cause still unidentified despite troubleshooting attempts
- Frequency reduced but still occurring (weekly/bi-weekly)
- Next step: escalate to W7 product owner for resolution
- Porsche meeting was unproductive, no solution found

### Action Items

- Oliver: Schedule meeting with Catherine to discuss AI enhancements display requirements and back & forth counter specifications
- Check with service desk ASMs regarding ticket report requirements for SAP for me
- Escalate replication issue to W7 solution owners for root cause analysis

---

Chat with meeting transcript: [https://notes.granola.ai/d/6c7c88f6-8140-43e5-8b21-2994012a72a3](https://notes.granola.ai/d/6c7c88f6-8140-43e5-8b21-2994012a72a3)
