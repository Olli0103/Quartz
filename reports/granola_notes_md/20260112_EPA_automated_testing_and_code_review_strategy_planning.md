# EPA automated testing and code review strategy planning

- Note ID: not_vzuBf6nHaundUh
- Created: 2026-01-12T10:36:47.852000+01:00
- Updated: 2026-01-14T10:05:24.957000+01:00
- Note Date: 2026-01-12
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Current Testing Process & Challenges

- EPA environment serves 10-20 customers with application monitoring dashboard
  - Getting 80% data from ESX, growing significantly this year
  - Stability challenge as customer base expands
- Current manual testing approach insufficient
  - Development happens across 5 parallel software components
  - Weekly deployment cycle: Friday morning build → Friday afternoon production schedule → Sunday deployment
  - Only manual testing: clicking through tiles, navigating apps in demo environment
  - No formal testing between developer testing and production

### Automated Testing Solutions

- Three potential approaches identified:
  1. OPA UI5 framework for Fiori applications
    - Native SAP technology, preferred for customer-facing expertise
    - Need to verify Build Work Zone support within iFrames
  2. Cloud ALM synthetic user monitoring
    - Already have Cloud ALM tenants in dev and production accounts
    - Meeting needed with Adi from testing team for guidance
  3. Python with Playwright framework (fallback option)
- Requirements:
  - Must test through UI (not just OData services) to validate full user experience
  - Screen scripting approach for browser automation
  - Execute Friday 6-12 AM UTC with error notifications
  - “Placebo” level acceptable - smoke testing for basic stability

### Code Review Automation & Next Steps

- GitHub Copilot automated code review investigation
  - Available in SAP’s enterprise GitHub
  - Automatic review triggers on pull requests
  - Challenge: ABAP backend code not currently pushed to GitHub (only Cloud Foundry apps)
- Action items:
  - Ammar: Check OPA UI5 framework compatibility with Build Work Zone
  - Oliver: Set up meeting with Adi (testing team) for Cloud ALM guidance
  - Michael: Ask Frank Jensen about ABAP Git connectivity options in upcoming meeting
- Focus on EPA environment first, extend to ESX after establishing working solution

---

Chat with meeting transcript: [https://notes.granola.ai/t/e7c4b904-661b-4556-885e-d5ecc6001e4c](https://notes.granola.ai/t/e7c4b904-661b-4556-885e-d5ecc6001e4c)
