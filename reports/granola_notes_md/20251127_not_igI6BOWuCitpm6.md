# Untitled

- Note ID: not_igI6BOWuCitpm6
- Created: 2025-11-27T09:31:12.354000+01:00
- Updated: 2025-11-27T10:19:03.448000+01:00
- Note Date: 2025-11-27
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: Projects

### Dashboard Development Progress

-   Navigation panel completed for CAS analytics center
    -   Landing page shows all pages/reports regardless of user authorization
    -   Two links per page: direct access + wiki documentation
    -   Status tracking moved from dashboard-level to individual pages
-   Page-specific development status:
    -   Backlog analysis & delivery performance: confirmed and released
    -   Audit control page: confirmed and released
    -   Contract management: waiting for Isabella’s UAT feedback
    -   Volume control & margin analysis: initial setup done, currently in UAT phase

### Service Performance & Adoption Data

-   Heavy calculations needed to identify package adoption/consumption
    -   Adoption requires initial kickoff ticket on specific components
    -   Each package has different customer-specific components
-   ESP data cleanup in progress
    -   Custom packages need AI analysis to identify underlying components
    -   Same package can have different contract descriptions (e.g., “KSAO custom”, “CarsAppOps custom”)
-   Consumption logic for fixed packages:
    -   100% consumption shown once activated (not percentage-based)
    -   Clear documentation needed on calculation logic to avoid ASM confusion
    -   Difference between delivery data and outcome value must be communicated

### Customer Reporting Challenges

-   Current automation insufficient for ASM needs
    -   70% of reporting template can be automated
    -   30% requires manual ASM review of delivery documents
-   Resource constraints blocking BTP application development
    -   Technology solution exists (PDF generator, eCharts framework)
    -   Need BTP developers and PDF framework expertise
-   Delivery heads complained about inadequate fixed package information

### Next Steps

-   Stefan: Custom cast component calculations (2 weeks)
-   ESP: Provide OData service for consumption data (by January)
-   Tom: Set up dedicated customer reporting follow-up meeting
    -   Include ASM representatives and requirements submitters
    -   Define what’s possible today vs. future automation needs
-   Oliver: Follow-up call with Alfred on margin analysis KPI merging

---

Chat with meeting transcript: [https://notes.granola.ai/t/b3b4e3f6-c77e-478a-a385-07cc57b2aa6b](https://notes.granola.ai/t/b3b4e3f6-c77e-478a-a385-07cc57b2aa6b)
