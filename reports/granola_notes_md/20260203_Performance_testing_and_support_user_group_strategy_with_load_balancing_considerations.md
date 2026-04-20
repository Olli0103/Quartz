# Performance testing and support user group strategy with load balancing considerations

- Note ID: not_cysCLcLXlG1NeY
- Created: 2026-02-03T10:06:29.209000+01:00
- Updated: 2026-03-03T15:44:28.074000+01:00
- Note Date: 2026-02-03
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Production Issue & Root Cause Analysis

- Tom needs backend access approval to investigate production errors
- Current issue causing operational headaches
- Process: 48-hour clean run in quality environment before production promotion
- Still investigating root cause through system diagnostics

### Performance Testing & Monitoring Strategy

- Load testing approved by Tom, moving forward with implementation
- Dynatrace integration planned to complement load balancing
  - Will pinpoint issues in AI core vs backend vs pre-LLM stages
  - Faster problem resolution and performance insights
- White paper in development (couple pages) to justify tooling benefits
  - Focus on open source solutions to avoid licensing costs
  - Preparation for data lake capabilities later this year
  - Will include latency testing beyond just load balancing

### Support User Group Setup

- Meeting scheduled with Tom and Stefan tomorrow morning
- Defining requirements for similarity ticket assignment (80% confidence threshold)
- Addressing concerns about ticket flooding
  - 60-79% confidence range (Amber) needs careful management
  - Creating Azure AD group for appropriate colleagues
  - Implementing gates to prevent colleague overload
- Strategic preparation for future data lake operations

### Next Steps

- Tom to approve backend access for production investigation
- Tomorrow: Support user group requirements session with Tom and Stefan
- Oliver to have Tom include speaker in Zebra-Stefan meetings for technical clarity and moderation
- Continue roadmap updates as sentiment analysis progresses

---

Chat with meeting transcript: [https://notes.granola.ai/t/22aaf0a8-b1c5-4327-bce6-5675b9ca4161](https://notes.granola.ai/t/22aaf0a8-b1c5-4327-bce6-5675b9ca4161)
