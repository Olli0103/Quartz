# AI use cases and ESX migration planning with security documentation review

- Note ID: not_3bzf5zXNE60atd
- Created: 2025-11-27T11:04:39.892000+01:00
- Updated: 2026-03-03T14:48:43.861000+01:00
- Note Date: 2025-11-27
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Information

- AI use cases require security documentation and approval from CPI team for ESP integration
  - Same process previously used for ESP implementation
  - Need to document how customer data is handled, access rules, and architecture overview
  - Security architectural design document needs updated paragraphs for AI use cases
- Current AI implementation resides in AMM FEC account (described as “messy playground environment”)
- ESX migration timeline targeting early 2026
- Cost analysis currently difficult due to mixed environments - ESX will enable better cloud reporting and cost identification

### Decision

- Oliver will provide security document template for required paragraphs
- Migration to ESX confirmed as necessary for productive use cases
- ESX will serve as collector for all delivery platform use cases, with AMM FEC remaining as development/research playground

### Action

- Security documentation update (1 week timeline)
  - Participant to update required sections in security document
  - Oliver to handle approval process with defense architecture colleagues
- User guide migration
  - Existing user guide to be provided in correct format
  - Oliver offered to migrate documentation to proper location
- ESX migration effort estimation
  - Participant to discuss with Bharat regarding required effort and timeline
  - Focus on understanding retraining requirements and data pipeline setup
  - App deployment itself not expected to be major issue

### Risk

- Migration effort estimation pending - Bharat previously reluctant due to perceived high effort requirements
- Continuous data flow and training pipeline setup complexity needs clarification
- Timeline pressure with early 2026 target for ESX migration

---

Chat with meeting transcript: [https://notes.granola.ai/t/28babf9a-90eb-4ab5-85f1-863a684549bc](https://notes.granola.ai/t/28babf9a-90eb-4ab5-85f1-863a684549bc)
