# Volume-based contracts and reporting strategy for CAS services

- Note ID: not_SjkJGJZYUx7PLL
- Created: 2026-02-05T08:59:50.389000+01:00
- Updated: 2026-02-05T14:34:43.559000+01:00
- Note Date: 2026-02-05
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Contract Transition Challenges

- Mid-month contract changes create complex billing scenarios
  - 48 tickets annually becomes 96 tickets in transition month
  - Customer confusion when double entitlements appear temporarily
- Current system shows misleading consumption data
  - Previous discussions with Steffen highlighted this issue
  - ASMs report customer confusion about fluctuating ticket counts

### Proposed Solutions for Mid-Month Contracts

- Option 1: Cut off old item, keep only new item
  - Shows current consumption for new period only
  - Loses historical data from previous period
  - Risk of artificially low consumption if new contract starts slowly
- Option 2: Create dual entries with filtering capability
  - Maintain both items in database for transparency
  - Add flag to exclude from dashboard graphics
  - Allow detailed drill-down at service/contract level
  - Preferred approach for raw data service

### Volume-Based Contract Considerations

- Rollover volume calculations remain complex
  - Hours carry over from previous months across periods
  - Question: Show contracted hours or actual available hours?
- Current contract landscape analysis needed
  - 433 monthly volume-based contracts still active
  - Includes EMS, SuccessFactors, BTP, VCX contracts
  - Some contracts extend through 2027

### Data Service Implementation

- Raw data approach recommended
  - Return multiple entries per month when applicable
  - Filtering handled at reporting/dashboard level
  - Maintains data integrity and transparency
- Reporting layer decisions deferred
  - May show only latest entry by default
  - Detailed view available for deeper analysis

### Next Steps

- Implement dual-entry system for mid-month transitions
- Investigate current volume-based contract usage patterns
- Determine reporting display preferences for transition periods

---

Chat with meeting transcript: [https://notes.granola.ai/t/068cb7bc-57df-4bd3-91e4-803edc16091e](https://notes.granola.ai/t/068cb7bc-57df-4bd3-91e4-803edc16091e)
