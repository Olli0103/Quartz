# SAP ADS Customer Entitlement AI Feature Planning with Team

- Note ID: not_iY4GXAGos86ayl
- Created: 2026-04-07T10:29:52.600000+02:00
- Updated: 2026-04-07T11:29:09.804000+02:00
- Note Date: 2026-04-07
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### ADS Entitlement Checker — AI Feature Idea

-   Colleague raised a pain point: consultants can’t quickly determine if a customer is entitled to ADS in their SAP account, their own subaccount, or not at all
    -   Currently requires checking Cloud Reporting, a 365-degree view, material numbers, and a mapping table
    -   Wrong answer in ~5 out of 10 cases despite the effort
-   Proposal: build a simple AI chatbot (“ADS Helferlein”) — ask “is this customer entitled?” and get a yes/no answer
-   Schenk has a Wiki-based guide documenting the current lookup process (shared during call)

### Volley AI Space — Proposed Approach

-   Could create a dedicated Volley AI Space (e.g. “ADS Helper”) and upload relevant mapping tables and source data
-   Key constraint: entitlement data changes as customers come and go — would need regular refresh (weekly or monthly)
-   Linking directly to a Wiki/SharePoint is not supported in the current setup — physical document uploads required
-   Best approach: Stefan does a bulk download of the relevant Cloud Reporting sources and loads them into the Space
-   ASM scenario currently has priority; this would need a dedicated owner

### Presentation Alignment (AI Ops / Application Management)

-   Working on a joint deck with Lalit (foundation layer) and another speaker (application layer)
-   Key decision: integrate both parts into the same slides, not separate sections
    -   Avoids perception that foundation and application management are two different things
    -   Goal: conversational/podcast style — Lalit sets up, next speaker builds on top, alternating
-   Need to add: AI support slide, six-pillar “Best Run” methodology slide, and a reworked legacy AMS vision slide
-   Deck appears to be a reused asset (not built from scratch for this occasion)

### Next Steps

-   Colleague (ADS topic)
    
    -   Set up a follow-up meeting with Schenk and Oliver to demo the Volley AI Space approach and clarify what data to upload
-   Oliver
    
    -   Align with Lalit on briefing call to agree on conversational presentation structure
    -   Share current deck status with the broader group for async feedback
    -   Connect with Manish and Jirak to review slide progress (vision/legacy AMS slide)
-   Manish
    
    -   Continue working on the overview/vision slide; sync with Oliver and Jirak as next step
    -   Integrate application management content into the shared deck
-   Team (all)
    
    -   Target: close the presentation in the next two weeks

---

Chat with meeting transcript: [https://notes.granola.ai/t/f4c865ae-d7be-44c0-859b-9e7774f9d73e](https://notes.granola.ai/t/f4c865ae-d7be-44c0-859b-9e7774f9d73e)
