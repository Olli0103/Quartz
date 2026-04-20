# AI Use Case Performance and Architecture Alignment with Tim

- Note ID: not_veGj3iZKTRZXfM
- Created: 2025-11-18T13:30:42.160000+01:00
- Updated: 2025-11-18T14:14:31.787000+01:00
- Note Date: 2025-11-18
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Information

- ESP team currently struggling with AI use case performance issues for weeks
  - Sentiment analyzer running poorly with critical performance problems
  - Ticket summary experiencing 25-45 second response times (currently disabled due to 45 seconds per ticket)
  - Target performance is 10 seconds for ticket summary generation
- Current ESP system architecture includes:
  - Three-tier landscape (dev, test, prod)
  - Ticket search and vector database in HANA Cloud on BTP
  - AI core implementation for sentiment analysis, similarity search, and ticket summarization
- Live features currently operational:
  - Ticket summary (disabled due to performance)
  - Similarity search (working acceptably)
  - Sentiment analysis (experiencing errors, no response from interface/modules)
- Tim’s background: 20+ years solution architect and project manager at SAP, extensive data experience, recent 3-year engagement at [booking.com](http://booking.com) rationalizing multiple SAP systems and implementing AI solutions
- Current production environment serves \~2000 consultants including suppliers
- Seba joining as developer pod contact starting Monday

### Decision

- Focus Q4 roadmap on two priority use cases: sentiment analysis and ticket summary
- Tim granted BTP cockpit access to dev, test, and production environments for AI APIs
- Team will follow Matthias’s recommendation for multiple API approach to work around 502 error (confirmed not a bug)

### Action

- Tim to schedule technical deep-dive meeting with Stefan and/or Marius this week
  - Review current system implementation and architecture
  - Understand ticket summary and similarity search functionality
  - Oliver to be CC’d on meeting invite
- Continue alignment discussions with Seba beginning next week
- Tim to review Matthias’s email regarding load distribution across environments
- Team to explore multi-API solution design and batch processing to address rate limiting issues

### Risk

- Performance bottlenecks threaten productive business operations with 2000+ users
- Current development team (Marius, Stefan) fully booked with delivery tasks, limiting AI development capacity
- 48k ticket backlog needs processing once performance issues resolved
- Sentiment analysis job failures creating gaps in emotional tone monitoring
- Year-end deadline pressure for delivering functional AI use cases

---

Chat with meeting transcript: [https://notes.granola.ai/d/30e05f40-1d85-4847-ba69-3813232328dd](https://notes.granola.ai/d/30e05f40-1d85-4847-ba69-3813232328dd)
