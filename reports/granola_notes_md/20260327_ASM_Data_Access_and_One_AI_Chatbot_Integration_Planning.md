# ASM Data Access and One AI Chatbot Integration Planning

- Note ID: not_3MSmGlBXfw54aT
- Created: 2026-03-27T11:03:10.644000+01:00
- Updated: 2026-03-27T13:31:41.758000+01:00
- Note Date: 2026-03-27
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### ASM Chatbot Implementation Discussion

- Steffen consultation raised more questions than answers
- Excel analysis shows more use cases than actual data sources
- Need direct ASM input to identify all data sources and locations
- Wiki documentation incomplete for some systems

### Technical Implementation Options

- Joule vs One AI chatbot approach
  - Joule: Full system access (tickets, documents, contracts)
  - One AI: Document-only initially, simpler to implement
- Phased rollout strategy recommended
  1. Start with One AI for documents
  2. Migrate to Joule for full functionality
  3. Maintain same access point in launchpad

### Data Integration Challenges

- ESP-X system integration uncertain
  - Need to verify if system data accessible or document-only
- SharePoint integration available for document grounding
  - Requires quality-controlled data upload
  - CPI-T ticket needed for SharePoint connector setup
- Wiki content extraction
  - PowerPoints and Excel attachments need manual download
  - Must be separately uploaded to grounding system

### Current System Status

- Existing ingestion pipeline available
- Documentation accessible in SAPEL
- Automatic updates possible when new documents added
- SharePoint pipeline can be configured for ASM-specific folders

### Next Steps

- Steffen meeting with ASMs to identify required data sources
- Document current ASM information needs outside existing systems
- Review ECS chatbot example (attached)
- Begin with document-focused implementation
- Set up SharePoint data quality process

---

Chat with meeting transcript: [https://notes.granola.ai/t/d2f977c4-c84c-4336-9a0e-8ce45cf293bb](https://notes.granola.ai/t/d2f977c4-c84c-4336-9a0e-8ce45cf293bb)
