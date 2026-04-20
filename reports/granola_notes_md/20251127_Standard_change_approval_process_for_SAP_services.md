# Standard change approval process for SAP services

- Note ID: not_az7h7X780sFQxD
- Created: 2025-11-27T13:30:03.609000+01:00
- Updated: 2025-11-27T13:58:58.250000+01:00
- Note Date: 2025-11-27
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Information

- Standard change approval process being developed for SAP services to enable proactive task execution
  - Currently only implemented for application security updates
  - Goal is to get pre-approval for basis tasks without requiring individual ticket approvals
  - Collaboration with SAP managed integrations team revealed overlap but different use cases
- Service request approach confirmed for implementation
  - Two service requests: one for opt-in, one for opt-out
  - Will be integrated into existing service request app
  - Approval stored as service request in SPC system
  - White paper will contain task list details (IP restricted, not publicly published)
- Current scope focuses on non-critical proactive tasks
  - SAP note implementation
  - RFC connections creation
  - Security-related activities from monitoring
  - Alert remediation activities
  - Performance monitoring follow-up actions

### Decision

- Standard change approval will be implemented through service request templates rather than adding to contracts
- Process will be mandatory part of customer onboarding for ASMs
- ASM will open service request on behalf of customer, customer approves through review process
- Task categories will remain fixed initially, with examples rather than exhaustive lists
- Implementation will start with activities that currently block progress when approval is delayed

### Action

- Oliver to trigger internal service enablement process with Stefan
  - Timeline: 3-6 months for productization
- Team to provide list of alert remediation activities for pre-approval consideration
- Development request needed to add standard approval field visibility in SPC for delivery teams
- Process integration required for ASM onboarding procedures
- White paper updates to include approved task categories and examples

### Risk

- Customer-specific requirements may complicate standardized approach
  - Some customers want approval for each remediation task
  - Others prefer minimal involvement except for downtime activities
- Implementation complexity increases if customer-specific approval lists are required
- Delivery team visibility of approvals needs technical solution in SPC system
- Parameter changes require careful consideration due to potential system impact

---

Chat with meeting transcript: [https://notes.granola.ai/t/3799c108-09b5-415b-941b-514a9964431d](https://notes.granola.ai/t/3799c108-09b5-415b-941b-514a9964431d)
