# ESP - Alignment on Solution Evaluation

- Note ID: not_d0780kWzI19hq3
- Created: 2025-08-25T14:00:31.322000+02:00
- Updated: 2026-03-03T11:39:39.118000+01:00
- Note Date: 2025-08-25
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: ESP - Alignment on Solution Evaluation
- Scheduled: 2025-08-25T14:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Solution Evaluation Implementation

-   Currently using push method followed by emotional tone and similarity endpoints
-   Solution evaluation endpoint unclear - when to call and what results to expect
-   Returns evaluation + 5 similar tickets, but most tickets lack solution descriptions
    -   GPT can evaluate from different perspectives (quality, tone, business language)
    -   Technical evaluation limited without proper solution data
-   **Decision**: Provide action button for select users (support team, Manuela) to test manually
    -   Avoid automatic calls due to performance overhead
    -   Analyze usefulness before broader rollout

### Performance Issues with Anonymization

-   Current orchestration service (SAP) causing 20-40 second delays
    -   LLM requests complete in 2 seconds without anonymization
    -   Ticket summary taking up to 30 minutes, causing system hangs
-   **Solution**: Revert to first version with built-in anonymization
    -   Processing time reduced to ~3-4 seconds total
    -   Uses standard NLP library, adds 2GB to application
    -   Remove emails, mask persons, keep organization names
-   Magnus deploying updated version to ESD after meeting for testing

### LLM Model Changes

-   GPT-4 32k abruptly removed by OpenAI without announcement
    -   GPT-4o available but runs automatically in background
    -   GPT-5 installed locally but not suitable for professional tasks
-   Switching to Gemini model
    -   Very good quality but requires prompt adaptation
    -   Extremely critical/biased - worked extensively on unbiased prompts
-   Cost concerns for large-scale processing
    -   Current plan insufficient for 10,000+ tickets
    -   Considering self-hosted LLM deployment (tested GPT OSS 20b locally)

### Next Steps

1.  Magnus: Deploy first version anonymization to ESD today
2.  Oliver: Coordinate testing of solution evaluation with select users
3.  Team: Research cost-effective self-hosted LLM options for scale
4.  Monitor performance improvements and gather feedback

---

Chat with meeting transcript: [https://notes.granola.ai/d/0579b798-a62d-4650-9764-49ee70d945c4](https://notes.granola.ai/d/0579b798-a62d-4650-9764-49ee70d945c4)
