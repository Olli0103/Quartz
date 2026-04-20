# AI & NewTech

- Note ID: not_RFI0uHkEjO0rNW
- Created: 2025-09-04T08:30:40.492000+02:00
- Updated: 2025-09-22T20:22:19.292000+02:00
- Note Date: 2025-09-04
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: AI & NewTech
- Scheduled: 2025-09-04T08:30:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### AI App Development Requirements

- Need 3 apps total: anomaly remediation, Intel image analysis, anomaly prediction
  - Priority: Remediation and prediction apps are critical
  - Intel image (SBPA automation) is low priority
- Estimated effort: 15-20 days development time
- Abhijit unavailable due to BTP advocate fellowship until December
- Malathi (SAP developer) not suitable for UI development
- Build Apps approach attempted but failed due to formatting issues requiring Ajax coding

### Resource Allocation Discussion

- Bruce heavily committed to Toyota project
  - Clean code dashboard work: 4 out of 10 allocated days wasted due to competing priorities
- Oliver to check with Pools/Tong colleagues for development support
  - Bruce Lee as main contact for coordination
- CAP application preferred over Build Apps for better user experience and backend model building

### Clean Code Dashboard Enhancements

- Alex assigned 2 tasks:
  - Minor: 3 small tasks requiring 5 days (using existing IO staffing)
  - Major: BTP monitoring without Efram implementation
    - Estimated 20-30 days effort
    - Requires analysis before Jira creation
- Current limitation: BTP core operations requires PCA customer status
  - Custom BTP customers can’t access monitoring without private cloud setup
- Application monitoring to be incorporated directly from BTP
  - Includes commercial, technical, and new application monitoring layers

### Product Issues Identified

- Unknown user entries in audit logs creating customer concerns
  - Found in internal tenant, could affect customer deployments
  - Product team updating SAP help documentation (currently in draft)
  - Audit log service team investigating customer communication needs
- Clean code dashboard deployed to 2-3 customers, 5-6 more in queue
  - BMW proposal by Christian in progress

### API Integration Challenges

- Michael enthusiastic about API usage possibilities
- CX AI data link team API available but requires legal approvals
- Security notes API concerns:
  - Direct customer exposure risky
  - AI recommends 500+ notes initially
  - Implementation cascades to additional note requirements
  - Validation of results challenging before customer deployment

### Next Steps

- Oliver: Check with Pools/Tong colleagues for development resource availability
- Bhakrav: Create Jira for major clean code dashboard task
- Bhakrav: Follow up on legal approvals for API usage
- Michael discussion needed on security notes integration approach

---

Chat with meeting transcript: [https://notes.granola.ai/d/19110125-441e-427a-bc96-b12749f6d9d0](https://notes.granola.ai/d/19110125-441e-427a-bc96-b12749f6d9d0)
