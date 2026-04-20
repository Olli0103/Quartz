# Cloud ALM AI Resolution and Monitoring Strategy Update

- Note ID: not_h8Y797D9Gvm5jZ
- Created: 2026-04-02T13:34:13.589000+02:00
- Updated: 2026-04-07T08:30:28.738000+02:00
- Note Date: 2026-04-02
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Cloud ALM AI Roadmap — Key Capabilities

- Alerting simplification: moving away from manual metric/threshold selection toward threshold-less dynamic alerting
  - Dynamic thresholding already live in Synthetic Monitoring; rolling out to Health Monitoring now
  - Change Point Detection / Pattern Detection in Exception Monitoring: Q2–Q3 2026
- CSA (Configuration Security Analysis): AI-assisted policy creation via natural language → Q3 2026
- Full anomaly detection without manual monitoring selection: 2027 target
- Agent-based configuration (conversational/agentic): in progress, shipping this year
- Joule is the frontend layer across all AI use cases in Cloud ALM
  - Follows One Joule architecture
  - Current blocker: customer-managed Joule tool not permitted per latest governance decision; SAP-managed tool doesn’t exist yet → team proceeding anyway (“better ask forgiveness than permission”)

### AI Resolution & Agent Architecture

- Current: “Solving Tips” (knowledge base suggestions) — acknowledged as weak
- Near-term: AI-assisted resolution → step-by-step guided remediation based on detected error, landscape-specific
  - Analogous to a dynamically generated guided procedure
  - Shipping soon (this year)
- Root Cause Analysis Agent: read-only, no system changes → lowest risk, highest confidence
  - Frank Wenske is PM for both AI System Alert Resolution and the Analysis Agent
- Problem Resolution Agent (auto-fix in target system): last priority, not this year
  - Requires high confidence in solution correctness before any write operations
  - Needs API integrations into target systems; significant build effort
- Scope: all Cloud ALM monitoring use cases, not just one; starting with root cause analysis
- Knowledge base grounding: SAP Notes + [help.sap.com](http://help.sap.com) indexed; ticket access in progress (approval obtained, compliance hurdles remain)
- AI credits: all AI features consume credits; pricing details to be clarified by Christian at a separate event
- Automation integrations (e.g. AutoPai, BCS): Cloud ALM calls external automation tools; customer must own the automation solution
  - MCP server integration possible in future but not confirmed

### Next Steps

- Oliver
  - Contact Xavier (Sabier?) to get access to a test system to evaluate current AI features
    - Note: test systems are highly unstable; \~50% uptime expected
  - Connect with Frank Wenske for a deeper dive on AI System Alert Resolution and Analysis Agent (suggest lunch when in the office)
  - Follow up with Jagadeesh (GTM, Cloud ALM transition from Solution Manager) re: Google tenant deal details

---

Chat with meeting transcript: [https://notes.granola.ai/t/0bf38f24-99c0-45c9-9b51-b742fcbeacc6](https://notes.granola.ai/t/0bf38f24-99c0-45c9-9b51-b742fcbeacc6)
