# AI Anomaly Model Training and Data Lake Strategy Update

- Note ID: not_7At3KUm5DEEpqF
- Created: 2026-02-05T08:00:04.288000+01:00
- Updated: 2026-02-05T09:03:06.159000+01:00
- Note Date: 2026-02-05
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Team Health Check & Project Status

- Team member recovered from yesterday’s illness, back on track
- Regular check-in on ongoing projects and blockers

### Intelligent Alloy Production Rollout

- Production deployment ready
- Rollout plan in preparation for sharing
- Access distribution to larger audience pending plan completion

### Model Accuracy Challenges

- Struggling with prediction accuracy results
- Meeting scheduled today for detailed review with additional test inputs
- Exploring new approach with complete algorithm redesign
  - 380GB training data vs previous selective metrics approach
  - Training time: 17 minutes (1 month data) vs 4-8 hours (6 months data)
  - Per-system training implemented to avoid data mixing issues
  - Customer-specific flexibility added for metric selection
- Time constraints major challenge for progress
- Michael blocking simple delta token implementation despite provided documentation

### Resource & Collaboration Options

- Potential collaboration with UPS team (different use case but ML expertise)
  - Their focus: system availability across landscape
  - Could provide offline code reviews as ML experts
- Frank Allen’s team discussion ongoing
  - Different mathematical approach being explored
- Team member Ankita learning well but requires guidance
- Knowledge sharing gaps identified with Sanjeev

### AI Infrastructure Migration & Strategy

- Migration from ESB to Services & Support data lake in progress
  - Governance review with Carol Bitznick (AI support infrastructure)
  - POC planned for AI use cases on migrated data
  - Ticket data already available in data lake
- Current AI use cases built on ESB BTP landscape
  - Vector database approach with AI Core/Launchpad
  - LLM orchestration without specialized training models
  - Fast implementation but not optimized

### Agent-Based Automation Architecture

- HCSM agent already resolving 3-5% of product support tickets
  - 3-minute response time with 90%+ confidence threshold
- Architecture includes specialized agents:
  - Deflection agents
  - Output agents
  - Data retriever agents
- Potential integration discussion with Jens Toddzki (HCSM AI lead)
  - Leverage agent solutions up to recommendation point
  - Pick up implementation from recommended solutions

### Duet for Consultants Integration

- API access discussion for leveraging existing knowledge base
- Previous request denied 7-8 months ago due to paid content concerns
- Meeting scheduled February 25 with product manager
  - Explore prompt engineering via API
  - Send anonymized ticket text for recommendations
- Would benefit multiple teams beyond current use case
- Security authentication could address misuse concerns

### Next Steps

- Complete anomaly detection v2 development
- Follow up on February 25 Duet for Consultants meeting
- Share HCSM agent architecture slides
- Continue model accuracy improvement efforts
- Wiki page review deferred due to current priorities

---

Chat with meeting transcript: [https://notes.granola.ai/t/50e35f20-0e28-47c7-8672-a3cdc81f8443](https://notes.granola.ai/t/50e35f20-0e28-47c7-8672-a3cdc81f8443)
