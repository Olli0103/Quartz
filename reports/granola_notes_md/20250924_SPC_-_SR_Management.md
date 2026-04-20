# SPC - SR Management

- Note ID: not_WY4XaHoE4huy1S
- Created: 2025-09-24T15:00:27.668000+02:00
- Updated: 2025-10-01T16:47:36.167000+02:00
- Note Date: 2025-09-24
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Calendar Event: SPC - SR Management
- Scheduled: 2025-09-24T15:00:00+02:00
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>
- Folders: 1:1s

### Current health status and recovery

- Still recovering from illness but mostly better
- Has some lingering after-effects but nearly fully recovered
- Now has immunity protection after going through the illness

### SPC service management strategy discussion

- Foundation service will handle majority of business (€89M pipeline in Q3/Q4)
- Current ticket flow processes \~120 cases
- Technical services strategy:
  - Keep technical services in SPC for now (temporary decision)
  - Foundation customers use Private Cloud catalog in SR App
  - Functional services (AMS, Testing) remain separate
  - Easier customer experience: technical vs functional service distinction rather than ECS vs CAS distinction

### Service catalog and component management

- Need new XXCaS components mirroring existing XXAmS components
  - Basis, Monitoring, Security, Performance, Data components required
  - Manual setup needed - no automatic migration
  - Contact Kathrin and Jana for component creation
- Component routing challenges:
  - XXAmS components → ESP routing
  - XXCaS components → ServiceNow routing
  - Timing depends on entitlement management capabilities

### Entitlement management challenges

- No current entitlement checking capability in ServiceNow
- ESP-based entitlement will continue for now
- Foundation customers need entitlement verification for both:
  - Service requests (via SPC)
  - Cases/incidents (via ServiceNow)
- Risk of customers opening wrong ticket types - need service desk training

### Legacy customer transition planning

- Need comprehensive overview of existing contract customers
- Analysis required:
  - Current customer count on old contracts
  - Contract expiration timelines
  - Renewal possibilities and restrictions
- Decision needed: manual handling vs technical solution for remaining legacy customers
- Consolidation opportunities for 34 individual catalog items

### Next steps

- Contact Kathrin/Jana re: XXCaS component creation
- Create customer contract overview analysis
- Discuss catalog consolidation with service owners
- Clarify entitlement management roadmap with delivery teams
- Confirm technical services remain in SPC transition plan

---

Chat with meeting transcript: [https://notes.granola.ai/d/e90a6c5e-2f48-4508-b4e3-efe843f90a58](https://notes.granola.ai/d/e90a6c5e-2f48-4508-b4e3-efe843f90a58)
