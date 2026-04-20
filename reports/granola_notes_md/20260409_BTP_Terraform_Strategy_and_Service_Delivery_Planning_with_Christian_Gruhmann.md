# BTP Terraform Strategy and Service Delivery Planning with Christian Gruhmann

- Note ID: not_L3hXcydOlj1jYr
- Created: 2026-04-09T10:02:05.685000+02:00
- Updated: 2026-04-09T10:23:45.205000+02:00
- Note Date: 2026-04-09
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Project Status Updates

- Time recording application progressing well
  - EPA work completed with minimal API requirements
  - Customer reporting functionality on track
- ESX migration nearly complete
  - All applications successfully moved
  - Database import and dual part still pending
  - Jessica assigned to test migrated applications
- Extended deadlines by 3 months across projects
  - HCSM PI extension includes ESP and PO systems
  - MAP features moved from MAP 2 to current MAP release

### Customer Reporting Challenges

- Timeline slipped from April to May delivery
- External developer dependency causing delays
  - Progress slower than expected
  - Limited direct control over delivery pace
- Sprint planning improvements implemented
  - Added team sprint meetings
  - Enhanced dashboard with story phases
  - Better project planning for external user onboarding

### BTP Administration & Security Issues

- Current subaccount access too permissive
  - All developers receiving subaccount administrator access
  - Uncontrolled HANA cloud instance creation (costly)
  - Insufficient audit logging for resource tracking
- Role-based access control needed
  1. AI developers → AI space access only
  2. CAP developers → CAP-specific access
  3. Report consultants → Reporting-specific access
- Chinese colleagues requesting SP system data integration into business data cloud

### Terraform Implementation Strategy

- Required for environment consistency across dev/quality/production
- Current manual processes unsustainable as system grows
- Proposed architecture
  - Repository-based Terraform with GitHub integration
  - Pipeline-triggered operations
  - Automated resource provisioning and state management
- Potential for centralized service delivery approach
  - Single Terraform environment with customer credentials
  - Leverage BMW’s existing BTP Terraform templates

### Next Steps

- Oliver to schedule joint call with Christian Gruhmann (BTP lead)
  - Discuss BMW template integration
  - Explore centralized vs. customer-specific deployment options
- Document current project status in goals/comments system
- Continue ESX migration completion with Jessica testing

---

Chat with meeting transcript: [https://notes.granola.ai/t/e4caaf15-471a-442c-b6ba-6ee022e7c677](https://notes.granola.ai/t/e4caaf15-471a-442c-b6ba-6ee022e7c677)
