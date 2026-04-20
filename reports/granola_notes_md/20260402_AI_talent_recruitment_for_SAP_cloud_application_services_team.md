# AI talent recruitment for SAP cloud application services team

- Note ID: not_zpiKhJR0nm85fi
- Created: 2026-04-02T11:29:53.325000+02:00
- Updated: 2026-04-02T12:31:58.206000+02:00
- Note Date: 2026-04-02
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Candidate Assessments

- Two candidates interviewed for AI developer roles on the SAP team
- Candidate 1 — clear no
  - Lacked depth on BTP; couldn’t go into technical detail when pushed
  - Mark tried to pull him deeper, but he kept stepping back out
- Candidate 2 — leaning no, but Mark wants to reconsider
  - Focused heavily on chatbot use cases; raw LLM capability felt light
  - Struggled with the multilingual RAG/similarity search diagnostic question
    - Couldn’t identify chunking or translation pre-processing as root causes without prompting
  - Oliver also not convinced: “too focused on automation, not the integration/pipeline development we need”
  - Mark: “the depth wasn’t there for either of them — yesterday’s candidates just flew, bang bang bang”

### Technical Interview Highlights (Candidate 2)

- LangGraph: described conditional routing via a travel booking agent (flight, hotel, car, trip planning)
- Human-in-the-loop / state persistence: handled via Redis/POST request storage; chat context retrieved on user return
- Confidence scoring: threshold-based flagging (use-case dependent, e.g. 90% or 50%); validation scripts post-LLM call
- Structured output failures: added a second LLM validation node to reformat string outputs into JSON
- Multilingual RAG issue: defaulted to prompt engineering and language detection libraries; didn’t surface chunking or embedding-layer issues unprompted

### Next Steps

- Oliver

  - Brief Mark after the call, then get feedback to Andrea today (before Easter weekend)
  - Tell George and Tom: both candidates are a no — request new profiles for a technical Python developer and an automation/integration engineer

- Mark

  - Confirm candidate 2’s CET availability and willingness to work CET hours
  - Follow up with Thomas (on leave) re: ServiceNow data access
  - Follow up with Sander on the ServiceNow side — last contact was early March, response felt like a stall
  - Come back to Oliver within the hour with final verdict on candidate 2

---

Chat with meeting transcript: [https://notes.granola.ai/t/994f7f1c-159e-449a-ba52-06fb43eea093](https://notes.granola.ai/t/994f7f1c-159e-449a-ba52-06fb43eea093)
