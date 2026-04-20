# ESX Launchpad app inventory and role management strategy with Jessica

- Note ID: not_O8ibKPoX2U52tU
- Created: 2026-04-09T11:36:31.793000+02:00
- Updated: 2026-04-09T12:06:13.184000+02:00
- Note Date: 2026-04-09
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Launchpad Testing Exercise Overview

- Core objective: Smoke testing role mechanism for new launchpad
  - Request role via ARM → app appears → quick functionality test
  - Process must work for all applications before go-live
- Target go-live date: June 1 or July 1 (to be decided by core team)
  - Decision makers: Tom, Oliver, and Omar
  - Timeline depends on thorough testing completion

### Application Inventory & Catalog Creation

- Building comprehensive Excel catalog on SharePoint
  - Current apps plus additional ESX-developed applications
  - New apps don’t exist in old environment
- Catalog structure includes:
  1. Title (what appears on launchpad)
  2. Subtitle
  3. HTML5 app ID (if applicable)
  4. ARM role required
  5. Type (hub, cup, simple URL link to ESP, etc.)
  6. Status/last test date
  7. Semantic objects and actions (extracted from URL)
- Knowledge distribution critical - can’t rely on just Tom and Oliver

### Current Testing Status

- Jessica sees only 1 app (Cast Delivery Dashboard) on new launchpad
  - Should see 3 apps based on current roles
  - Issue likely related to launchpad copy/alias configuration
- Old launchpad shows \~5 apps for Jessica
- Role verification needed in ARM system
  - Jessica has Cast Consultant role
  - Additional roles may be required

### Technical Configuration Issues

- Multiple launchpad versions causing confusion:
  1. Released version (for Chinese colleagues - Excel upload only)
  2. Temporary testing version (site UX suffix)
  3. Final production version
- Omar investigating role replication between old/new launchpads
- Alias and default site settings need adjustment

### Next Steps

- Oliver will create and share formatted Excel inventory template
- Jessica schedules working session with Omar and Tom
  - Investigate missing app visibility
  - Understand role-to-app mapping
- Jessica commits 1 day per week average to this exercise
  - Flexibility for 2 days some weeks as needed
  - Continuous weekly progress essential due to complexity
- Monthly ESX Launchpad meeting invitation for Jessica
- Additional new apps to be added to inventory bottom section

---

Chat with meeting transcript: [https://notes.granola.ai/t/f392cbb0-c240-4bf2-bfd3-cd84643f989b](https://notes.granola.ai/t/f392cbb0-c240-4bf2-bfd3-cd84643f989b)
