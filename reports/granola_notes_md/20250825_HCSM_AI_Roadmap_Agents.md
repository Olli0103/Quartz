# HCSM AI Roadmap / Agents

- Note ID: not_lgpHdiAbLQVbq1
- Created: 2025-08-25T09:30:59.998000+02:00
- Updated: 2025-09-22T20:22:20.311000+02:00
- Note Date: 2025-08-25
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: HCSM AI Roadmap / Agents
- Scheduled: 2025-08-25T09:30:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Current AI Implementation & ServiceNow Migration

- Running custom ticket system with 650,000 tickets in BTP landscape vector database
- Built AI scenarios for ticket management:
  - Sentiment analysis for consultant alerts
  - Ticket similarity search
  - Resolution recommendation system (consultant inputs solution, AI validates against database)
- Migration to ServiceNow planned for next year
  - ESP system will remain for legacy customers
  - Need to maintain AI capabilities in new environment

### AI Model Development Strategy

- Data replication approach: tickets flow from ServiceNow to Data Lake (similar to current support model)
  - All tickets anonymized before reaching Data Lake
  - Existing models can plug back into ServiceNow
- Selective development philosophy:
  - Use ServiceNow out-of-the-box features when “good enough” (e.g., sentiment analysis)
  - Build custom models only when domain knowledge provides significant advantage
  - Solution recommendation system (8 years running) remains custom-built
- Auto Response agent now live (3 weeks):
  - Handles \~1% of tickets without human intervention
  - 2-5 minute response time
  - Clear AI attribution in responses
  - 9-month ethics review process completed

### Agent Orchestration Challenges

- Major limitation: attribute mapping between unstructured LLM outputs and structured APIs
  - Example: “Schedule meeting with Oliver Thursday 3pm” lacks required specificity
  - APIs need exact parameters (user IDs, timezones, duration, etc.)
- Current success rates problematic:
  - Single agent: \~33% success rate
  - Multi-agent chains: drops to \~3% (compounding failures)
- SAP building 80+ MCP servers but orchestration remains challenging
- Current approach: deterministic “flows” rather than full agent autonomy
  - Smaller, reliable patterns first
  - Learn successful patterns before expanding orchestration

### Next Steps

- Contact Thomas Ansorge (Program Lead) and Karl Blissner (Chief Data Governor) for Data Lake integration
- Explore Intelligent Frontdoor program with Corinne Reisert
  - Unified customer experience across Case/Service Request distinction
  - Early stage development (started 1-2 months ago)
  - Goal: conversational routing to appropriate channels

---

Chat with meeting transcript: [https://notes.granola.ai/d/87b91e44-d1ec-48a4-8c8a-323666bfaf32](https://notes.granola.ai/d/87b91e44-d1ec-48a4-8c8a-323666bfaf32)
