# Weekly production and service updates with Oliver

- Note ID: not_mytSIbhW403PWM
- Created: 2026-02-05T15:09:39.488000+01:00
- Updated: 2026-02-06T08:15:12.177000+01:00
- Note Date: 2026-02-05
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Production Updates & Issues

- Similar tickets OWARF Heatherburg fix deployed to production
- Sentiment smoke test passed in production
- New critical issue: Gateway error 502 on sentiment API
  - Intermittent failures over last 8 hours
  - 6 dropouts recorded overnight
  - Silver conducting root cause analysis
  - Number one priority for service team

### HSCM Meeting with Alex

- Third meeting (previous one had no attendees)
- Focus on case management and incidents from alerts
- Strong interest in detailed use cases
  - Opportunity for them to build functionality on our use cases
  - Potential leverage for new use cases they want us to work on
- Proposal to share use case summary with more detail
  - Current deck too light on specifics
  - Will include ServiceNow contacts and peer HSCBM colleague activities

### Infrastructure & Monitoring Progress

- Dynatrace connected to dev environment (Omar’s assistance)
  - Access issue: Two-factor authentication grayed out
  - Prompting for Radius connection instead of Microsoft app
  - Omar helping resolve tomorrow
- Plan to use for root cause analysis once access sorted
- Progression path: Dev → QA → Production

### Load Testing & Monitoring Stack

- K6 load testing session with Tom and Stefan
  - Agreement on approach, some reservations about Amber state KPI support
  - Setup instructions ready, deployment after sentiment issue resolved
  - Target: Functional by end of next week
- Prometheus and Grafana for dashboards
  - Alternative to BTP environment visuals
  - Support function workflow with ticket assignment options
  - Tagging and reassignment capabilities

### Next Steps

- ESP session next Wednesday to confirm stability gate
- Share detailed use case summary with Alex’s team
- Resolve Dynatrace access with Omar
- Deploy K6 after sentiment API fix
- Continue biweekly connects with Abujay’s team to avoid double development

---

Chat with meeting transcript: [https://notes.granola.ai/t/447d7a31-35bb-46af-b353-5f99fc4c3419](https://notes.granola.ai/t/447d7a31-35bb-46af-b353-5f99fc4c3419)
