# AI Ticket Automation and Resource Planning with Oliver

- Note ID: not_Z7dgztkBsZCptv
- Created: 2026-03-09T14:29:57.774000+01:00
- Updated: 2026-03-09T15:32:40.256000+01:00
- Note Date: 2026-03-09
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Kaz Intelligence Engine Development Update

- 10-node agent architecture complete with synthetic data
  - Live ticket intake → escalation decision → notification → human approval workflow
  - LangGraph orchestration layer confirmed as optimal approach
  - GitHub repo populated with full architecture
  - Target completion: Wednesday/Thursday this week
- Sentiment tracking enhancement needed
  - Store sentiment history per ticket vs. current single-point capture
  - Escalation trigger: bad sentiment persists after customer reply
  - Implementation in USX database rather than ESP
- Production considerations flagged
  - AI will directly update HANA database vs. current human engineer process
  - Security and data governance requirements for productionization
  - Change management sensitivity noted for German workforce

### Resource Capacity and Demand Management

- Multiple workstreams creating capacity pressure on Sylvia
  - HCSM: 9 use cases from Alex’s team currently parked
  - SuccessFactors: Clear requirements from Yasef emerging
  - Stefan/Tom: 3 additional use cases in backlog
- Resource request approval needed
  - February profiles still valid as minimum requirement
  - Demand may exceed original estimates due to multiple channels
  - Recruitment timeline: 1-6 weeks depending on supplier availability

### Compliance and Next Steps

- AI use case repository documentation required
  - Intelligent Use Case Repository process for each AI implementation
  - AI ethics impact assessment and Microsoft forms completion
  - Process recently changed - investigation needed on new Jira requirements

### Action Items

- Oliver: Send email with AI compliance process details after investigating recent changes
- Team member: Send resource requirement profiles to Oliver this afternoon
- Oliver: Forward resource requests to Andrea (supplier management)
- Team: Demo preparation for Vinay in May continues on track

---

Chat with meeting transcript: [https://notes.granola.ai/t/98e39b8e-b7bf-4b49-a57e-5b5aab9f0737](https://notes.granola.ai/t/98e39b8e-b7bf-4b49-a57e-5b5aab9f0737)
