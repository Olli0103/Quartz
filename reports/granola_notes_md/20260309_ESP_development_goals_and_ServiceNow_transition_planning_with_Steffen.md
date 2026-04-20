# ESP development goals and ServiceNow transition planning with Steffen

- Note ID: not_kiC4QBBXstJ0xj
- Created: 2026-03-09T10:32:47.766000+01:00
- Updated: 2026-03-09T13:01:55.708000+01:00
- Note Date: 2026-03-09
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Current Workload & Challenges

- Overwhelming parallel work streams
  - More change requests than team can handle simultaneously
  - New reporting requirements with Tom and Ama for ticket data/escalation history in ESX-HANA database
  - Seller monitor activation pending - needs queue monitoring to prevent backlogs
  - Replication problems intermittent but manageable
- Constant ad-hoc requests from various stakeholders
  - Difficult to decline help requests while maintaining relationships
  - Context switching between multiple urgent priorities
- Team capacity constraints
  - Need to prepare background information for team members lacking meeting context
  - Documentation requirements for new processes like reporting systems
  - Rework cycles when initial approaches need adjustment

### AI Sentiment Analysis Implementation

- ESP deployment readiness
  - Mark requested Friday changes requiring ESP resync
  - Color-coded sentiment indicators (traffic light system) ready for rollout
  - Need Jana/Isabell documentation and rollout preparation
- Enhanced monitoring capabilities
  - Agent alerts when multiple red sentiment tickets from same customer
  - Proactive escalation to DC heads (Rafa, Papette, Hau) with ASM involvement
  - More granular than current manual monitoring by Manuela
- Historical sentiment tracking potential
  - Current system overwrites sentiment scores on ticket updates
  - Proposed: Separate historical analysis in HANA ESX storage
  - Could track consultant response effectiveness vs. recommended actions
  - Decoupled from real-time algorithm to avoid performance overhead

### Problem Management Agent Development

- Multi-agent architecture approach
  - Orchestrator/team manager distributing tasks to specialized agents
  - Communication agent, analysis agent, solution agent, documentation agent
  - Prevents LLM hallucination issues with large, complex tickets
- Proactive problem identification
  - Auto-creates problem records when 90% similarity score across multiple tickets (2-3 days)
  - Automatic solution evaluation and root cause analysis
  - Per-customer problem record creation (e.g., V-Hon functionality issues)
- Current gap in ITIL process
  - No proactive problem management currently
  - Incidents handled as problems instead of proper ITIL separation
  - Missing incident → problem → change workflow

### Performance Goals & ServiceNow Transition

- 2026 goal setting approach
  - 2-3 focused personal goals vs. previous 4-6 diluted objectives
  - Direct impact on performance KPI (3.6-3.8 range) affecting salary/bonus/promotions
- Proposed focus areas for team member:
  1. ESP development leadership - 90% weekly change request SLA compliance, monthly TLR alignments, 3+ process automation features
  2. ServiceNow transition preparation - learning/development goals for platform migration
- Timeline considerations
  - March 31st deadline for final goal submission
  - Quarterly reviews integrated into 4-week meeting cycles
  - René prefers separate COI development vs. Conrad CEO integration
  - ESP development team transitioning to ServiceNow support structure

---

Chat with meeting transcript: [https://notes.granola.ai/t/6a1ba722-8904-4552-bf57-9459b7dc98dd](https://notes.granola.ai/t/6a1ba722-8904-4552-bf57-9459b7dc98dd)
