# Agentic AI and Automation Strategies for ESP and SPC

- Note ID: not_xDXhaPCFv67fvj
- Created: 2026-03-02T07:00:34.885000+01:00
- Updated: 2026-03-02T07:49:39.307000+01:00
- Note Date: 2026-03-02
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### AI/Agentic Development Discussion

- Current monitoring system provides anomaly prediction with confidence scores for next 30 minutes
  - Statistical prediction available but unclear if ML/deep learning involved
  - Intelligent alert remediation exists but not fully autonomous
  - System analyzes alerts, triggers BPA, gathers info, sends to consultants
  - No self-healing capabilities - requires human interaction per SAP AI ethics policy
- MCP server deployment blocked by SAP red tape internally
  - Direct customer deployment possible without SAP permission (clean code approach)
  - Could leverage autonomous functions if deployed in customer environment
- Winnie pushing hard toward agentic direction for marketing purposes
  - Need POCs ready for Sapphire discussion with Lalit/Peter
  - Winnie willing to provide resources from anywhere needed

### SPC Integration & Capabilities

- SPC Fuel contains existing intelligent root cause analysis (non-agentic)
- Available agents include:
  - Assisted Service Request (ASR) agent - reviews requests, suggests templates
  - Q3 extension planned for ASR to perform actions
  - Safeguarding agent for risk assessment
  - Troubleshooting agents in development
- ServiceNow already achieving 3-5% autonomous case resolution
  - Complete resolution in 5 minutes vs 6 months traditional approach
  - High customer satisfaction with speed
- Potential agentic use case: ESP ticket → agent picks up SAP note implementation request → calls SPC automation → auto-implements → documents
  - Would require UI automation or APIs (currently unavailable)
  - Only solution appears to be Windows BPA

### Process Automation & Technical Challenges

- Playwright testing completed 1.5 years ago for BTP release notes scraping
  - Works for static HTML but fails with JavaScript rendering
  - Snowflake solution also inadequate for deep JavaScript rendering
- API access needed for consolidated release notes from BTP
  - Would prevent customer outages by providing advance notice of changes
  - Currently blocked by SSPL access restrictions
- Docker containerization implemented to maintain stability despite SAP product changes
  - Prevents library conflicts and breaking changes
- IST hub integration should minimize manual effort
  - Route data via existing APIs (ease eggs, EPA)
  - System not ready for full automation coverage yet

### Next Steps

- Oliver: Alignment with Shantano today on service delivery automation programs
- Team: Create ideal repository for use case prioritization and planning
  - Identify quick wins vs red tape blockers like MCP server
- Check with PTP product colleagues on MCP server permissions
- Tomorrow: Call regarding Dalian pre-visit (Oliver and others attending)

---

Chat with meeting transcript: [https://notes.granola.ai/t/b336a52e-d86c-435a-a2e2-093b74593bdf](https://notes.granola.ai/t/b336a52e-d86c-435a-a2e2-093b74593bdf)
