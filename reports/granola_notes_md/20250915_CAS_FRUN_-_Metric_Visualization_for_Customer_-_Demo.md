# CAS FRUN - Metric Visualization for Customer - Demo

- Note ID: not_w7xQslvWFo181G
- Created: 2025-09-15T16:31:35.981000+02:00
- Updated: 2025-09-22T20:22:19.292000+02:00
- Note Date: 2025-09-15
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: CAS FRUN - Metric Visualization for Customer - Demo
- Scheduled: 2025-09-15T16:30:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### CAS EFRON Metric Visualization Architecture

- Three-layer architecture for customer metric visualization

  - Layer 1: CAS EFRON (single tenant, ACS managed, \~6,000-7,000 instances from \~3,000 systems)
  - Layer 2: BTP environment (ESX, internal tooling layer, single tenant)
  - Layer 3: Customer dashboard (multi-tenant BTP, SaaS-like with enterprise isolation)

- Current data extraction process

  - Daily API calls to extract all system instances
  - Main API called every 50 minutes with 8 parallel threads
  - Generates \~3M records per day, targeting 13 months retention (1B+ records)
  - Extracts system monitoring data into flat cross-customer table

- Planned Q1/Q2 architecture change

  - Switch from pull to push architecture from CAS EFRON to middle layer
  - Reasons: performance issues with standard API, resource optimization, API limitations (200 time series max)
  - Custom Z program implementation under development

### Customer Dashboard Interface

- Operation Applications Cockpit launched via dedicated customer tenants

  - Single sign-on integration with customer identity providers
  - Multi-application launchpad including EFRON visualization
  - Target users: IT users, IT key users, some business process key users

- Current visualization features

  - Default Health Monitoring
    - Table format with filtering capabilities
    - System-level aggregation (average calculations)
    - Drill-down to individual metrics with time navigation
  - Application Performance monitoring
    - Similar structure to health monitoring
    - Metrics include dialog response time, front-end response time

- Future enhancements planned

  - More aggregated and abstract visualizations based on customer feedback
  - Alert data integration
  - Improved UI for customers with hundreds of systems

### Internal Usage Discussion

- ECS internal dashboard consolidation interest expressed

  - Use case: Single view across multiple productive EFRON environments
  - Operational control center topics and root cause analysis overview
  - Technical feasibility confirmed but requires L1/L2 level discussion

- Current limitations for large-scale internal usage

  - UI designed for single customer scenarios
  - Performance challenges with thousands of systems
  - Reuse potential mainly in extraction layer (left side architecture)

- Data source clarification

  - Only pulls from CAS EFRON system monitoring (not direct system access)
  - Also integrates with customer Cloud ALM for batch jobs, web services, integrations
  - No direct connection to original source systems

---

Chat with meeting transcript: [https://notes.granola.ai/d/9526080e-fc53-472d-92c3-0abc0eba0b06](https://notes.granola.ai/d/9526080e-fc53-472d-92c3-0abc0eba0b06)
