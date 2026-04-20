# Weekly project status and AI enhancement review with team

- Note ID: not_7NWaeZJoJJw62g
- Created: 2026-01-14T08:00:14.653000+01:00
- Updated: 2026-01-14T10:02:19.776000+01:00
- Note Date: 2026-01-14
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Project Status Updates

- Solution time supplier report
  - No feedback received yet after transport
  - Need to check if Tom received any information
- Hack EMS customer report
  - Last update from December 10
  - Tom to provide status update on missing updates
- Customer reporting application
  - New project team assembled and ready
    - Project manager onboarded
    - BTP cap developer onboarded
    - Second BTP cap developer onboarded
  - Waiting for feedback from Andrea to proceed
  - Two cap developers pending purchase approval from Andrea

### Development Completions

- Customer reporting Excel generation (Sri)
  - Developer completed work, delivered to guest yesterday for testing
  - Testing on ESP environment (cannot test on ESD/ESQ due to lack of real data)
  - Report generation only, not sending to ASAMs - just to Tom
- Supply Management report
  - Parked since November, not current priority
- Process automation for recurring tickets
  - Erica waiting for time recording completion before pickup
  - May work simultaneously on other priorities
  - Pending alignment meeting with Jana Kreuzeger

### AI Enhancement Progress

- Massive performance improvement achieved using Nano model
  - Promoted to dev environment and tested
  - Stefan to validate sentiment analysis today (planned yesterday but delayed)
  - Performance testing priority in ESD, real data testing in ESP
- Current scope: emotional tone/sentiment only moved to Nano
- Ticket evaluation remains on Gemini LLM
- Next phase: expand Nano to other functional use cases after sentiment validation

### System Maintenance & Infrastructure

- Automatic notification for expired contracts
  - No change in status
  - Tom to create CR for ticket
- ServiceNow interface
  - Missing information, no updates
- Application time reduction
  - Transported and rescheduled to run every minute
  - Total application time still \~6 minutes (unchanged)
  - 9 minutes remaining against 15-minute IRT for P1
- Automated refresh implemented in ESP since this morning
  - Catherine approved rollout
  - Will mention in team meeting, no formal rollout to other users

### Security & Technical Issues

- Batch user profile removal from ESD/ESQ completed
  - Security issue identified and resolved
  - No issues observed with running jobs
  - ESP implementation scheduled for Monday
  - Full week monitoring planned before month-end processing
- SBC shadow ticket automatic closure
  - Interface bug between ServiceNow and SBC
  - \~5,000 tickets require manual closure via program
  - Working to reduce manual processing volume
- Ticket replication downtime yesterday evening (resolved)

### Next Steps

- Stefan: Complete sentiment analysis validation today
- Tom: Update Hack EMS customer report status
- Tom: Create CR for expired contract notifications
- Schedule Monday meeting for ESP batch user profile changes
- Monitor system performance after security changes

---

Chat with meeting transcript: [https://notes.granola.ai/t/4e8d74b3-d91e-44dc-9b6d-306028d81dca](https://notes.granola.ai/t/4e8d74b3-d91e-44dc-9b6d-306028d81dca)
