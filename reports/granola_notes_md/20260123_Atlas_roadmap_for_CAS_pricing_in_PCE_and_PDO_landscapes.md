# Atlas roadmap for CAS pricing in PCE and PDO landscapes

- Note ID: not_hWiqXEtXoMPSev
- Created: 2026-01-23T16:04:00.278000+01:00
- Updated: 2026-01-23T17:43:56.615000+01:00
- Note Date: 2026-01-23
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### CAS Integration in Big Deal Architecture

- CAS element present in all major deals signed in December
- Objective: seamless customer experience across Rise, CAS, and Cloud ERP
- High attach rate for new technical package approach versus previous smaller CAS packages

### Current Implementation Status

- MVP implementation operational
  - CAS attached to quotes for price list items and custom parts
  - Integrated with subscription order management
  - Continuous maintenance post-booking
- Missing component: custom configuration and pricing handled separately
  - Same manual process as order form contribution
  - Creates operational inefficiency

### Pricing Model Differences: PCE vs PDO

- PCE (Private Cloud Edition):
  - Automated derivative pricing in Harmony
  - Percentage uplift system (standard \~12%)
  - CAS, DR, and EUS handled as uplifts
  - Two new CAS columns added to eligible SKUs list
- PDO (Private Deployment Option):
  - Manual pricing process required
  - Landscape configuration approach (not percentage-based)
  - All components (EUS, DR) bundled into single landscape SKU
  - Revenue attribution requires Atlas breakdown for invoicing

### Process Challenges & Workarounds

- PDO manual process:
  1. Take full landscape from indicative pricing form
  2. Apply reductions for non-CAS cost drivers
  3. Calculate uplift on eligible PDO landscape baseline
  4. Execute via Excel-based manual pricing
- C2C deals complexity:
  - Year-based entitlement model (Year 1: up to 7 landscapes, Year 2: up to 12)
  - Fixed monthly charges to avoid repricing on landscape shifts
  - “Gray zone” approach - not directly linked to every landscape change

### Next Steps

- Schedule follow-up with Paul’s team this month (preferably)
- Two priority road map items for 2026:
  1. CAS for PCE package (#80206512) - expected to be straightforward like other uplifts
  2. New PDO model development - requires significant development work
- Thomas to send email with Atlas SharePoint links highlighting two follow-up topics
- Check PC package customer contracts for CAS attachment status

---

Chat with meeting transcript: [https://notes.granola.ai/t/d30636c3-2a81-4e78-97f0-51571809f369](https://notes.granola.ai/t/d30636c3-2a81-4e78-97f0-51571809f369)
