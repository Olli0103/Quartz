# Automation and AI strategy for customer support and monitoring

- Note ID: not_PYYmmJ5a3Z0eIF
- Created: 2026-02-06T16:00:52.456000+01:00
- Updated: 2026-02-06T16:41:27.697000+01:00
- Note Date: 2026-02-06
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Travel and Work Plans

- Flying to aunt’s location for cycling sport in different region
- 1.5 hour flight, \~500km distance
- 2 weeks work remaining before vacation
- Next week working from Medellin SAP office
- Plan to test 1-2 cycling routes over weekend, then full cycling during vacation

### Cloud ALM Implementation Progress

- Team concerns about 130-person team capacity addressed
- Katrin Gläsner and team initially skeptical but now understand scope
- Cannot risk losing incidents with hundreds of customers
- Old manual processes being replaced with automated systems
- Cloud ALM allows direct target component creation without X-XAMS workaround
  - Tickets land directly in ESB
  - Can close tickets automatically via API calls
  - System stable under production conditions

### Service Delivery Challenges

- 30 contracts exist but only 15 in ESP system
- Many contracts valid from January 1st still missing
- Some old contracts still active despite new ones being valid
- Data quality issues identified as separate from core service
- First customer (Agrolimen) workshop postponed - customer overwhelmed by SAP teams
- Mercedes likely to be first implementation
- ASMs increasingly contacting directly for faster responses

### Monitoring and Automation Strategy

- Dynatrace BTP service setup in progress for AI monitoring
- €15.40 per host unit cost structure
- End-to-end monitoring planned: AI Launchpad, ESG, ESX Cloud Connector
- Current latency issues with Google Cloud models (45 seconds vs 3 seconds with GPT-4-Mini)
- Future automation vision:
  - Daily system cleanup without customer involvement
  - Knowledge base building for AI-powered support
  - Transition from reactive to proactive problem solving
  - Reduced manual intervention through intelligent automation

### Team Performance Issues

- Giancarlo development concerns:
  - No visible progress on E-Front alerts development (1.5 weeks)
  - Not accessing development systems
  - Frequent offline periods
  - Committed to February 28th delivery date
- Need Berlin meeting to address performance directly
- Development task should take 2-5 days with existing templates

### Next Steps

- Set up Dynatrace monitoring system
- Address Giancarlo performance issues in person
- Continue customer onboarding preparations
- Monitor contract activation timeline for potential bottlenecks

---

Chat with meeting transcript: [https://notes.granola.ai/t/92650960-89ca-46e3-9e36-f0949a1e4186](https://notes.granola.ai/t/92650960-89ca-46e3-9e36-f0949a1e4186)
