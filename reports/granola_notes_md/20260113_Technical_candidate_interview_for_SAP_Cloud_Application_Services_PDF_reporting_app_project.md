# Technical candidate interview for SAP Cloud Application Services PDF reporting app project

- Note ID: not_GIgOF6T8aywSVu
- Created: 2026-01-13T10:28:30.969000+01:00
- Updated: 2026-01-14T10:03:10.710000+01:00
- Note Date: 2026-01-13
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Project Context & Role Overview

- Platform team within SAP Cloud Application Services providing cloud subscription-based solutions
- Building automated customer reporting app to replace manual PowerPoint process
  - Dynamic KPI selection and sequencing for Application Service Managers (ASMs)
  - PDF generation with configurable metrics/charts
- Team structure: 5 core members
  - Overarching architect (Tom)
  - Project manager
  - BT solution architect (Amit)
  - 2 CAP developers (data + PDF focus)

### Candidate Background - Technical Experience

- 13+ years development experience, 5 years focused on BTP services
- BTP services worked with:
  - Feature flags, DMS, Document AI (formerly Document Information Restriction)
  - Audit log, application scalar, connectivity, destination services
  - Success Factor extensibility
- Systems integration experience:
  - ECC to S4HANA (versions 21, 22, 23, FPZ 01-02)
  - Public/private cloud configurations
- Recent AI/automation work:
  - Multiple AI chatbots using SAP AI Core/Launch
  - MCP server development with CAP on Cloud Foundry
  - DevOps tools: GitHub, Jenkins, SonarCube
- Product development: 2 products listed on SAP Store for real estate industry

### Technical Assessment Discussion

- PDF generation approach options:
  1. Node.js libraries with custom positioning logic
  2. Adobe services on BTP for form creation
- Configurable reporting challenges:
  - Text positioning and overlap prevention
  - Dynamic content based on user selections
  - Graph integration in PDFs
- CAP development preferences:
  - Business Application Studio over VS Code for BTP integration
  - Custom column addition via manifest.json and UI.LineItem annotations
- Authorization implementation:
  - Access security JSON for role templates/scopes
  - Attribute-based access control (company code example: 1000, 2000, 3000)
  - Role collection hierarchy: Role Collections → Roles → Scopes → Attributes
- Frontend experience: Fiori elements, custom UI5, flexible programming model

### Decision & Next Steps

- Candidate demonstrates strong technical knowledge but talks extensively
- Both this candidate and Abhijit (previous interview) capable of PDF development
- Project needs 2 developers - can work in parallel
- Decision timeline: Response via Josh within 2-3 days (max end of week)
- Candidate availability: Ready once partner discharged from hospital (likely tomorrow)

---

Chat with meeting transcript: [https://notes.granola.ai/t/f8e237b8-d61a-45f5-93dc-d6439112be0d](https://notes.granola.ai/t/f8e237b8-d61a-45f5-93dc-d6439112be0d)
