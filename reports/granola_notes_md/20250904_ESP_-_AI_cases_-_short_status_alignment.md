# ESP - AI cases - short status alignment

- Note ID: not_NWSGw20tokksPT
- Created: 2025-09-04T14:03:04.026000+02:00
- Updated: 2026-03-03T14:54:41.635000+01:00
- Note Date: 2025-09-04
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: ESP - AI cases - short status alignment
- Scheduled: 2025-09-04T14:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### AI Launchpad Connection Issues

- ESP AI features experiencing multiple problems
  - Ticket summary functionality not working
  - Connections between AI Launchpad and AI Core failing
  - Summarization engine producing hallucinated results
    - Content totally unrelated to input
    - Very inaccurate responses despite previous good results
- Only using single tenant in dev account for cost efficiency
- Regional problems suspected in current account setup
- Other AI functions (sentiment analysis, emotional tone analysis) still working fine

### Current Status & Investigation

- Stefan tested all different cases this morning
- Two distinct problems identified:
  - AI Launchpad to AI Core connection issues
  - Quality degradation in summarization engine
- Gemini 2.5 Pro model previously worked well
- BTP performance generally slow recently
- Access permissions issues preventing Oliver from opening AI Launchpad

### Proposed Solutions

- Create new AI Launchpad instance in production subaccount
  - Leave current dev instance for analysis
  - Temporary workaround while investigating
- Switch to alternative AI Core connection as test
- Stefan not optimistic about switching - suspects regional configuration issues
- Assign proper roles to Oliver and Stefan for direct access

### UI Development Progress

- Good progress made despite other tasks
- Struggling to get right data format
- Estimated completion: mid next week
- Waiting on BTP API restoration

### Next Steps

- Stefan: Update ServiceNow ticket with detailed problem analysis
- Stefan: Contact Juliana Freedom directly for screen sharing session
- Marius: Monitor ticket progress (Stefan unavailable tomorrow)
- Oliver: Monitor ticket and contact processors directly if needed
- Marius: Assign required AI Launchpad roles to Oliver and Stefan
- Test alternative AI Launchpad in different region

---

Chat with meeting transcript: [https://notes.granola.ai/d/c02e3525-1e8c-437a-bdbb-3a6e231ad59e](https://notes.granola.ai/d/c02e3525-1e8c-437a-bdbb-3a6e231ad59e)
