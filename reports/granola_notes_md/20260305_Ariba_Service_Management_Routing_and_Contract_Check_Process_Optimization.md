# Ariba Service Management Routing and Contract Check Process Optimization

- Note ID: not_NXU2mxlwzePqEI
- Created: 2026-03-05T10:34:35.207000+01:00
- Updated: 2026-03-05T11:06:37.467000+01:00
- Note Date: 2026-03-05
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Contract Management & Process Updates

- Package maintenance documentation needed for ASM team
  - Contract team (Isabella and colleagues) requires consultant assignment info
  - Documentation must specify who handles each contract
- Escalation process updates
  - René and Isabella should receive escalation notifications
  - Regional escalation matrix needs updating with function IDs
- Contract Management Team notification timing
  - Inform after Erika completes testing and system goes live

### Ariba Automation Implementation

- New CR created for automatic ticket routing on XXAMSARI component
  - Contract check → automatic process assignment → memo creation → forward to ServiceNow
- P2-P4 tickets: Full automation possible
- P1 tickets: Manual handling required initially
  - Escalation process handled by Aschock’s triage team
  - ERT fulfilled when ticket processed with info added
- Component mapping needed
  - \~20 Ariba components currently available
  - Ahmed to provide ESP to ServiceNow component mapping
  - All customer-selectable components need routing destinations
- Manual fallback process required when no contract found
  - Service desk needs instructions for manual forwarding
  - Template needed for forwarded tickets

### Solution Time Monitoring Concerns

- New contract model may include Solution Time requirements
  - Not standard in new Ariba contracts but possible in custom agreements
  - Current monitoring capabilities insufficient for ServiceNow environment
- Risk assessment needed for contracts with Solution Time clauses
  - Technical monitoring limitations identified
  - Process planning required before implementation
- Examples: NEOM project (now cancelled due to Iran situation), other potential custom contracts

### Next Steps

- Oliver: Email Ahmed requesting component mapping (CC: team)
- Team: Afternoon meeting scheduled (2:00-2:50 PM) with Katrin, Claudia, Jana, Stefan
- Stefan/Erika: Implement CR logic for automatic routing
- Gaby: Maintain service template overview list for new services

---

Chat with meeting transcript: [https://notes.granola.ai/t/f93b367b-0e7b-4543-97f1-a30f18e2fe14](https://notes.granola.ai/t/f93b367b-0e7b-4543-97f1-a30f18e2fe14)
