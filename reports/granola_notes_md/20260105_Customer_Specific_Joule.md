# Customer Specific Joule

- Note ID: not_jqAmnBcZNswnmd
- Created: 2026-01-05T16:31:43.980000+01:00
- Updated: 2026-01-14T10:12:25.314000+01:00
- Note Date: 2026-01-05
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### POC Progress & Customer Implementation

- Built extraction tools for ticket data analysis using AI Core
- Successfully tested with \~50 Votorantum tickets, generating positive feedback
- Current POC uses Joule in Votorantim account within AMSA BTC instance
  - Document grounding with MD files stored in S3 bucket
  - Working solution validated by team
- Next phase: Scale to all customer tickets with user segregation
  - ASM managers see all tickets from subordinates
  - Account-specific ASMs only access their assigned customer data

### Technical Architecture & Implementation

- Current setup: All ticket data in ESX environment
  - Connected to ESP and Business Data Cloud/Platform
  - Data replication from ESX to customer-specific EPA tenants
  - Vector engine database transfers segregated data to isolated customer tenants
- Customer tenant structure:
  - EPA SaaS environment with customer-specific access
  - Work Zone launchpad for customer dashboard access
  - IAS authentication with SAP-managed local user store
  - Current cost: \~$70/month for complete ESP stack (600k tickets)
- Planned enhancement: Full ticket body integration
  - Currently limited to ticket headers only
  - Need Tom Hansen coordination for full ticket access from Business Data Cloud
  - HANA Cloud instance required for vector storage (\~$100-200/month additional)

### Next Steps & Timeline

- Fernando: Create Jira ticket documenting requirements and services needed
- Michael: Provision Votorantum tenant (São Paulo AWS) within next week
  - Provide CAM role access for Fernando
  - Set up empty tenant with ticket header API endpoint
- 4-week follow-up meeting scheduled (post-go-to-market week)
- Security concept update: Include ticket data handling documentation
- Cost monitoring: Year-end review for next pricing cycle iteration
- Automation consideration: Terraform or BTP Automation Pilot for multi-customer scaling

---

Chat with meeting transcript: [https://notes.granola.ai/t/63149ded-c2c9-47d2-9d98-29395db62102](https://notes.granola.ai/t/63149ded-c2c9-47d2-9d98-29395db62102)
