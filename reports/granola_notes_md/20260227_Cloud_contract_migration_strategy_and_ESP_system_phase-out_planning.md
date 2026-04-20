# Cloud contract migration strategy and ESP system phase-out planning

- Note ID: not_6fNUQMl3jBwexT
- Created: 2026-02-27T09:06:01.749000+01:00
- Updated: 2026-02-27T10:05:06.059000+01:00
- Note Date: 2026-02-27
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Contract Platform Migration Strategy

- Legacy ESP system end-of-life: December 31, 2030
  - No patches or security updates after this date
  - System becomes non-auditable and unsafe for customer business
  - Maximum 2-3 months extension possible with L1/L2 support only
- Two delivery platforms currently in use:
  - Private Cloud: Fixed scope contracts via ISP
  - Public Cloud: Provider contracts via ICP using same platform as public cloud
- Integration complexity requires managing two platforms with special contract attributes
  - EMS system creates entitlements
  - Distribution back to ICP for SLA and routing
  - Direct delivery to customers for service calls

### Phase-Based Implementation Approach

- **Phase 1 (MVP - Light Green)**: New fixed-price Private Cloud contracts
  - Simplest to implement due to 1:1 mapping between SKUs and services
  - No hourly billing complexity
  - Priority for new business deals
- **Phase 2 (Dark Green)**: Custom Private Cloud contracts
  - More complex scope items and delivery requirements
  - Combined with Phase 1 to support complete new customer contracts
- **Phase 3**: Legacy fixed-price contracts (deactivated SKUs)
  - Lower priority items with fewer customers
  - Many expected to naturally phase out by 2030

### Out-of-Scope Decisions

- **EMS/AMS hourly-based services excluded from migration**
  - Built on legacy Hack contracts (Hack Classic, SDE Extended)
  - Requires underlying contract restructuring beyond project scope
  - Customer trend analysis shows decline: 622 customers (Feb 2025) → 437 customers (current)
  - Projected natural phase-out by 2030 if trend continues (\~150 customers/year reduction)
- **Risk identified**: If underlying Hack contracts not migrated, ESP must continue operating post-2030
  - High risk rating assigned
  - Requires board exception for continued ESP operation
  - Risk tracking and monitoring process to be established

### Customer Contract Analysis

- Current active SKUs categorized by:
  - New business (available on price list)
  - Legacy contracts (existing customers only)
  - Volume-based vs. fixed-price structures
- Success Factors customers often have mixed contracts (both fixed and custom components)
  - Critical to support complete new customer deals in single phase
  - Prevents split delivery across multiple platforms for same customer
- Cloud Application Services and other renamed services maintain old AMS hourly model despite new names

### Next Steps

- René to update phase classification in shared document
- Andreas to provide file access and links for collaborative editing
- Schedule follow-up meeting next week to finalize SKU categorization
- Risk register entry for EMS/AMS migration dependency
- Dashboard links added to speaker notes for EMS/AMS customer tracking
- Portfolio roadmap discussion with Georg postponed to next meeting (20-minute session needed)

---

Chat with meeting transcript: [https://notes.granola.ai/t/df3356d3-281b-4fec-98df-1bebfacd96b1](https://notes.granola.ai/t/df3356d3-281b-4fec-98df-1bebfacd96b1)
