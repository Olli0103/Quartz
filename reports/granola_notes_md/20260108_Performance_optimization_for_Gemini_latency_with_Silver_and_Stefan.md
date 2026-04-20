# Performance optimization for Gemini latency with Silver and Stefan

- Note ID: not_uLXMfiSRzEVXf4
- Created: 2026-01-08T15:01:07.586000+01:00
- Updated: 2026-01-14T10:07:05.358000+01:00
- Note Date: 2026-01-08
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Performance Issue Resolution

- Root cause identified: Gemini causing 88% of latency issues
- Current average response time: \~30 seconds
- Silver swapping Gemini to Nano model
  - Test results show reduction to 3 seconds
  - Ready for deployment tomorrow
- Rollout plan:
  1. Dev environment testing complete
  2. Stefan review in dev environment
  3. Quality environment deployment
  4. Production release
- Concern: Impact on Janet AI team with different LLMs

### HCSM Deck Review & Gap Analysis

- Deck shared and under review by Oliver
- Key clarification needed: GenAI cases in Work Zone
  - Only shows HCSM team-built cases
  - Missing ServiceNow built-in functionality (e.g., sentiment analysis)
  - Stream leads need to verify coverage
- Gap analysis completed with detailed link provided
- Deck restructured based on feedback: “building not adopting” approach
- Master requirements rewritten (version 5)
  - Shifted from solution architect to data scientist perspective
  - Simplified for non-technical colleagues

### Monday Session Planning

- Silver to join Monday session
- Stefan not included to keep team size manageable
- Follow-up planned with HCSM team leads post-session
- Requirements shared with Jessica for alignment

### Next Steps

- Silver: Deploy Nano model by tomorrow morning (dev environment)
- Oliver: Review updated master requirements document
- Polite follow-up with Thomas on approvals status
- Promote to quality environment after Stefan retesting
- Follow up with Jessica on requirements alignment

---

Chat with meeting transcript: [https://notes.granola.ai/t/c360d069-1b72-42c4-a4e7-5533466aefe3](https://notes.granola.ai/t/c360d069-1b72-42c4-a4e7-5533466aefe3)
