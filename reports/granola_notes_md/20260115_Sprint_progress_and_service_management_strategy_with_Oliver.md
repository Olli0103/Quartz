# Sprint progress and service management strategy with Oliver

- Note ID: not_m3u5HBVqaXQgQe
- Created: 2026-01-15T15:00:59.924000+01:00
- Updated: 2026-01-16T08:11:14.974000+01:00
- Note Date: 2026-01-15
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Sentiment Validation Performance

- Nano deployed successfully with Stefan’s validation
- Performance improved dramatically: <3 seconds vs previous 45 seconds
- Need useful ESD examples for content validation
  - Stefan working on timeline for this

### HCSM User Engagement Sessions

- Initial functional meeting went well, proceeding with engagement
- 5 meetings scheduled across different groups (including Tom)
- Cross-functional user group included
- 71% acceptance rate on meeting invites
- Questions tailored to individual responsibilities:
  - SR management events
  - Knowledge analytics
  - Case/incident management
- Oliver to receive updates on outcomes, not direct participation

### Technical Development Status

- Sprint focus on ticket 850 while awaiting Stefan’s testing
- Vector database issues found in foundation dataset
  - Must fix before improvements possible
  - Top priority for current focus
- QAS promotion ticket summary pending Stefan’s validation
- ServiceNow access obtained (CAS app)
  - Started with low privileges, now at second level
  - Working on data extract for gap analysis
  - Will inform ECS catalog recommendations

### ServiceNow Migration Insights

- Starting with zero dataset - no existing tickets migrated to data lake
- Use cases will run on tickets generated after migration point
- Opportunity to leverage broader datasets beyond portal boundaries
- 2.5M tickets available in ServiceNow for analysis
  - Plan to analyze last 90 days, then 12-6 month periods

### AI Agent Implementation Discussion

- Product support has auto-response agent handling 1-3% of tickets
- Agent operates with 90-100% confidence levels
- Takes over tickets within 3-5 minutes, provides solutions autonomously
- Potential to adapt for consulting cases but needs customization:
  - Route to internal queues vs back to customer
  - Adapt behavior for consulting workflow
- Opportunity to leverage existing infrastructure

### Jessica Thesis Support

- First meeting completed successfully
- Thesis deadline end of month - under pressure
- Given access to 9 use cases and Teams/SharePoint workspace
- Provided overview and guidance on priorities
- Follow-up sessions planned as needed

### Resource Allocation Concerns

- Stefan managing heavy ticket load causing delays
- Performance validation delayed pending content validation
- Stefan confirmed performance “very good” - content validation in progress
- Decision to parallelize work where possible
- Start proactive program management discussions with other team members
- Avoid blocking dependencies by working on parallel tracks

### Next Steps

- Stefan: Complete content validation (expected today)
- Continue sprint work on tickets 851, 853
- Begin discussions with Renee Coven on HCSM project elements
- Parallelize workstreams to minimize waiting periods

---

Chat with meeting transcript: [https://notes.granola.ai/t/6c3638f8-8b8a-4dc6-b2bc-5839f457c8f2](https://notes.granola.ai/t/6c3638f8-8b8a-4dc6-b2bc-5839f457c8f2)
