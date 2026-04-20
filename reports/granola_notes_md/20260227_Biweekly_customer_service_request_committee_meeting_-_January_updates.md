# Biweekly customer service request committee meeting - January updates

- Note ID: not_aG8n4mfJZhdy3I
- Created: 2026-02-27T13:00:30.924000+01:00
- Updated: 2026-02-27T14:34:10.426000+01:00
- Note Date: 2026-02-27
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### New Service Request Proposals

- Convert S4HANA to private cloud standards (renamed from “on-premise”)

  - Fixes 500 systems missing private cloud conversion
  - Required for AI features from BTP
  - Automation already exists, just cleanup work
  - Approved with name change

- SAP standard change approval for dev/quality systems

  - Legal requirement for pre-approved permissions
  - Chargeable service only for customers with CaaS contracts
  - One-time request per customer onboarding
  - 70-100 new customers annually expected
  - Approved

### Service Retirement

- Move HANA tenant to another database
  - No executions in past 2 years
  - All approvals from TEOs and CDL confirmed
  - Retirement approved

### SFTP Server Service Update

- Current volume: \~500 requests monthly

- Enhanced template with 5 options:

  1. Initial SFTP setup
  2. Additional SFTP users
  3. Password resets
  4. Secondary group additions
  5. Passwordless public key setup

- 2026 challenges and improvements:

  - Standardization focus for legacy setups
  - Tool limitations preventing individual home directories
  - ServiceNow credential access issues ongoing 2-3 months
  - New HCIS system automation planned for Q2
  - Red Hat system adaptation by Q2

- Security improvements implemented:

  - Stopped adding SFTP users to sepsis group
  - Added CDDM users to SFTP groups instead
  - Blocked SFTP usernames in CDDM format

### Network Firewall Rules Service

- Add/modify hyperscaler NSG firewall rules

- Volume: 400-500 tickets monthly

- Service excellence: 76% (improving)

- CES rating challenges: 70% rated 4-5 stars, 30% poor

- Key issues causing poor ratings:

  - Customer environment problems (firewalls, DNS)
  - Wrong template selection (inbound vs outbound)
  - Last-minute urgent requests during go-lives

- Automation progress:

  - Phase 1: Pre-check procedure in QA, production target March
  - Phase 2: Main procedure automation planned
  - First network service automation attempt (no reference available)

### Application Upgrade Service

- Major release upgrades for ABAP and Java components

- Recent duration optimization:

  - ABAP: Preparation increased 1→2 days, lead time 3→5 days
  - Java: Duration unchanged

- January KPIs:

  - Service excellence: 63.5% (below standard)
  - Customer effort score: 4.0 (good)
  - Procedure usage: 81.5%
  - Schedule adherence: 70.5% (low)
  - Customer callback rate: 89.1% (very high)

- Improvement initiatives in progress:

  - File system checks for CPU/RAM prerequisites
  - MPID automation via CLM API
  - Customer buffer input enablement
  - Manual task automation (SI checks, DB compatibility)
  - MRC dashboard integration to reduce callbacks

- Customer satisfaction issues:

  - Requests for faster updates (currently hourly)
  - Cockpit access expectations not met by default
  - Multiple customer confirmations causing delays
  - Rescheduling difficulties from portal

---

Chat with meeting transcript: [https://notes.granola.ai/t/d1a41a77-0d93-465f-a729-d0170d30f5f2](https://notes.granola.ai/t/d1a41a77-0d93-465f-a729-d0170d30f5f2)
