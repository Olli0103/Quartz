# Sentiment Analysis and AI Project Status Update with Martin

- Note ID: not_Hkc5mQtvT92rBy
- Created: 2026-02-27T15:01:14.318000+01:00
- Updated: 2026-03-02T06:49:39.298000+01:00
- Note Date: 2026-02-27
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### AI System Updates & Production Status

- Summarization phase 2 deployed to production yesterday
  - Running cleanly at 4+ seconds performance
  - Stefan confirmed good performance, Zulu monitoring
  - Dynatrace showcase on Wednesday ESP call received positive feedback from colleagues
  - Additional enhancements planned: KPI-aligned triggers (70% processor utilization amber, 80% attention threshold)
  - Application layer enhancements for root cause validation across LLM, HANA, SP, AI core
- Sentiment analysis v2.1 in QA
  - Calibration fix, gratitude detection, keyword bias all addressed
  - Janice’s 3 misclassified tickets resolved with constructive feedback applied
  - Reducing negative/incorrect AI response verifications
- Non-customer filter achieved 100% accuracy on 13 tickets
  - 70% of tickets filtered out (no customer voice)
  - 23% passing through to sentiment scoring
  - Data quality issues cleaned up by Silva
- Solution evaluation bug fixed, moving to QA alongside sentiment v2.1

### Resource Gaps & Ownership Issues

- Production gate ownership for sentiment unclear
  - Oliver proposed Manuela for sign-off responsibility
  - Quality review owner needed for amber-category responses requiring manual review
  - Manuela initially suggested but showed resistance to additional testing requests
- Testing capacity gap identified
  - Current team maxed out on testing workload
  - Need automated testing approach using Tricentis or similar tools
  - Scaling discussion needed: current “one man sprint team” (Silva) requires expansion
- Agentic AI priority emerging
  - Getting increased attention, needs to be incorporated into roadmap
  - Strategy session scheduled for next Friday

### Next Steps

- Martin: Contact Tom/Stefan directly for sentiment production gate ownership
- Martin: Complete slide deck for Friday AI session by Monday
- Oliver: Review white paper and discuss content in Monday 11am meeting
- Oliver: Confirm Michael’s attendance for Friday session (currently on vacation)
- Martin: Develop resource proposal for testing and development scaling
- Team: Prioritize agentic AI discussion for next week
- Jana: Confirm availability as sentiment quality review owner

---

Chat with meeting transcript: [https://notes.granola.ai/t/3cd623d1-d151-45f8-8b23-8ccfc276a958](https://notes.granola.ai/t/3cd623d1-d151-45f8-8b23-8ccfc276a958)
