# ESP and ServiceNow migration planning with Stefan

- Note ID: not_a7nbXfUhscaHu7
- Created: 2026-01-21T13:01:15.993000+01:00
- Updated: 2026-01-21T13:35:01.132000+01:00
- Note Date: 2026-01-21
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Cloud ERP Tool Management Challenges

- Current consultants lack proper permissions for component access
  - No one has project manager role for numerous components (Security, Data Monitoring, ADM)
  - Standard consultants can’t see all necessary tickets
- Quick solutions under consideration:
  1. Give everyone MOD or project manager role for full visibility
  2. Create new custom role
  3. Implement more maintenance-intensive ASMs

### Lead Consultant Integration Issues

- New lead consultant role needs comprehensive ticket overview and dispatch capabilities
- Current permission structure prevents cross-component visibility
- Lead consultant expected to handle ticket routing and monitoring across all areas
- Risk of limiting lead consultant to only TS queues would undermine the role concept

### ESP vs SPC Migration Strategy

- ESP removal not feasible due to ongoing incident management requirements
- Automation for recurring tickets (onboarding, customer-specific tasks) would be lost
  - Cloud API currently doesn’t support service requests
  - Automatic ticket creation from dashboard/application relations would cease
- ServiceNow Foundation implementation timeline discussion needed
  - Could start with basic foundation before full CARS business functionality
  - XXA customer data and XXKs OPS component mapping required

### Current System Dependencies

- Security teams have SPC queues but unclear usage levels
- Customer-facing queue remains XXAM
- Recurring ticket automation critical for current operations
- Complete process redesign required if moving away from ESP

### Next Steps

- Schedule meeting with Menu team to discuss ServiceNow migration feasibility
- Document comprehensive impact analysis of ESP removal
  - List all automation dependencies
  - Catalog required off-site extensions rebuild
- Prepare project manager role assignment list for immediate permission fixes
  - Include lead consultants and backup personnel
  - Submit to permissions team for implementation
- Evaluate whether to proceed with original SPC migration plan or maintain ESP status quo

---

Chat with meeting transcript: [https://notes.granola.ai/t/6bf7ad0d-671a-4c90-a30c-7b5a68ff0e96](https://notes.granola.ai/t/6bf7ad0d-671a-4c90-a30c-7b5a68ff0e96)
