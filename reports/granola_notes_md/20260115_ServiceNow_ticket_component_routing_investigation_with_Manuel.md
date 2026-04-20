# ServiceNow ticket component routing investigation with Manuel

- Note ID: not_DZnUchUFhvrMjV
- Created: 2026-01-15T11:01:25.113000+01:00
- Updated: 2026-01-15T12:11:14.945000+01:00
- Note Date: 2026-01-15
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### ServiceNow Ticket Component Issue

- Tickets automatically reverting from XXMS components back to XKS components after manual reassignment
- System undoing the workaround process that moves tickets from XXK → XXMS components to reach ISP
- BTP Monitoring ticket example: opened on XKS, moved to BTP component, then system reverted to K-S component
- Kathrin receiving alerts about unprocessed tickets due to incorrect component assignments

### Ticket Replication Status Check

- Yesterday’s batch: \~300 tickets on XXAMS components successfully replicated to ESP
- Dispatcher job confirming ESP receipt of tickets
- External reference numbers maintain sync between ServiceNow and ESP systems
- Out-of-sync risk minimal due to case number linking system

### Recurring Tickets Bot Development Progress

- Current state: JSON file-based metadata accessible via VDI Alex Murphy with Python scripts
- Next step: Migrate data from JSON to BTP HANA database for multi-user access
- Goal: Centralized control system for both ESP and future ServiceNow recurring tickets
- Master Data App integration planned for ASM self-service ticket creation

### Future ASM Workflow Automation

- Vision: ASMs create recurring tickets directly through Master Data App during contract setup
- Automatic ticket bot configuration based on service selections (security updates, monitoring, etc.)
- Eliminates manual intervention for standard recurring ticket requests
- Manual override capability preserved for ad-hoc ticket needs
- Collaboration required between Manuela (data preparation) and Omar (app development)

### Foundation Package Tickets Clarification

- Michael’s Foundation Package tickets are one-time service requests, not recurring
- Generated in ServiceNow when customers add new systems requiring F-brand monitoring connection
- Separate from recurring ticket bot system and BTP database migration
- Can occur multiple times per customer as infrastructure expands

### Next Steps

- Kathrin: Report new component reversion examples to Manuel for troubleshooting
- Manuela: Begin BTP database migration planning
- Team coordination meeting needed for Christiana/Jana workload distribution (forwarded to Jana for review)

---

Chat with meeting transcript: [https://notes.granola.ai/t/7ff696cc-0eeb-4883-b655-7dcdf52b3215](https://notes.granola.ai/t/7ff696cc-0eeb-4883-b655-7dcdf52b3215)
