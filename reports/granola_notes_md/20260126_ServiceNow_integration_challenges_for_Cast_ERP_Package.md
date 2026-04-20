# ServiceNow integration challenges for Cast ERP Package

- Note ID: not_vT38fsba8gpugB
- Created: 2026-01-26T14:01:20.245000+01:00
- Updated: 2026-01-26T16:20:57.984000+01:00
- Note Date: 2026-01-26
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### ServiceNow Transition Discussion

- Stefan’s team currently managing three separate tools:
  - ServiceNow for ECS incidents (PTO ops TSV)
  - SPC system for subscription/ESP workflows
  - Considering adding Cast for Cloud ERP Package to ServiceNow
- Challenge: Would create mixed workflow with ServiceNow + SPC instead of current three-tool setup
- Key concerns raised:
  - Service Desk integration complexity
  - Entitlement management gaps
  - Component migration from X-X-Arbeis to X-X-Ks required

### Technical Implementation Barriers

- Cast ServiceNow implementation not ready for production
  - Major project delays resolved recently
  - K’s implementation scheduled to begin March
  - No functional system available for current testing
- Entitlement system architecture:
  - EMS (Entitlement Management System) handles contract verification
  - ESP currently manages X-X-AMS component routing
  - ServiceNow lacks direct entitlement checking capability
  - Without proper entitlement, any customer could submit tickets to wrong queues
- Contract complexity:
  - Multiple contract types: Provider vs Subscription
  - Volume-based contracts remaining in ESP system
  - New contracts require ICP/EMS integration before ServiceNow migration

### Timeline and Recommendations

- Recommended approach: Wait for full EMS integration rather than premature pilot
- Proposed timeline:
  - November go-live target (pending L4 approval meeting February 4th)
  - Two development cycles needed (March-August)
  - Testing period before production launch
- Alternative interim solution discussed:
  - Temporary incident-only component without entitlement checks
  - Service Desk could forward tickets from ESP to Cast components
  - Requires separate assignment group creation
- ESP sunset concern: IT support ending 2030 with active contracts extending beyond

---

Chat with meeting transcript: [https://notes.granola.ai/t/c93f987b-efc6-468b-82dd-3cdd60565b99](https://notes.granola.ai/t/c93f987b-efc6-468b-82dd-3cdd60565b99)
