# Service desk tools and SPC integration workflow with Andrea

- Note ID: not_cN9APqfIzDCX1O
- Created: 2025-11-24T15:00:21.903000+01:00
- Updated: 2025-11-24T15:11:44.338000+01:00
- Note Date: 2025-11-24
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Service Desk Tool Integration & Monitoring

- Andresa working on tools/information requirements for service desk monitoring tickets
- Current setup: Service requests processed in SPC, monitoring via service request dashboard (not SPC)
- Plan: Service desk will use same dashboard with potential custom views/KPIs
  - May need specific tab for service desk KPIs
  - Data exists, just needs proper formatting/display

### Escalation Flow Changes

- Major change needed: Escalation button flow for CAST queues
  - Currently: All escalations go through ECS (even for CAST)
  - New plan: Direct escalation to service desk, removing ECS dependency
- Implementation appears straightforward
  - 5 escalation levels in SPC
  - Just changing communication flow parameters
  - No major tool modifications needed

### ASM Dashboard Access

- Proposal: Extend CMD dashboard access to ASMs for service request visibility
- Benefits: Holistic view of customer tickets by assigned accounts
  - Shows open service requests, status, incidents per ASM’s customers
  - More efficient than searching SPC ticket by ticket
- Requirements:
  - ASMs need CLM profile (already exists)
  - ASM assignments in DED (exists but needs cleanup)
  - Uses existing delivery coordinator role structure

### ServiceNow Migration Considerations

- Andresa meeting with Ned & Holger next week about ServiceNow transition
- Dashboard requirements must be included early in ITSM project demands
- Learning from ECS issues: Dashboard delays caused go-live postponement (November → December)

### Next Steps

- Andresa will deliver SPC training session tomorrow with Stephanie
- Any tool/platform requirements to be escalated to Oliver’s team
- DED-related changes can involve Nid (role harmonization expertise)
- Process discussions can go directly to Dirk/CLM team

---

Chat with meeting transcript: [https://notes.granola.ai/t/68ad006f-43cd-4c03-a441-3e69fed21d45](https://notes.granola.ai/t/68ad006f-43cd-4c03-a441-3e69fed21d45)
