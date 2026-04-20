# SAP BTP AI Ticketing System Candidate Interview with Sushi

- Note ID: not_qebIgmi40MjfCQ
- Created: 2026-04-01T11:29:52.885000+02:00
- Updated: 2026-04-10T11:16:38.336000+02:00
- Note Date: 2026-04-01
- Owner: Oliver Posselt <oliver.posselt@gmail.com>
- Attendees: Oliver Posselt <oliver.posselt@gmail.com>

### Candidate Overview — Ishi

- AI/ML QA engineer interviewed for quality & testing role on the LangGraph-based intelligence engine (SAP BTP)
- Strong signal across all technical areas — Mark’s assessment: “we’re not gonna get anybody better”
- One gap: BTP-specific depth felt slightly thin, but Mark confident it can be addressed given her overall skill level
- No hesitation on any questions; gave Mark good confidence she’ll drive quality at pace

### Technical Assessment Highlights

- RAG evaluation: built custom LLM-as-judge tooling on top of DeepEval/Ragas after identifying limitations
  - Prioritises context precision, faithfulness, answer relevance, toxicity/bias
- Similarity search testing: proposed embedding-based semantic scoring to automate relevance validation
- Confidence thresholds (green >80%, amber 60–79%, red <60%): would flag low-confidence outputs for human review
- Load testing approach: local endpoint first → non-prod → prod, benchmarking latency, throughput, p95, RPS
- LLM regression: semantic similarity + LLM-as-judge scoring across 10 prompts, tracking % change per release
- CI/CD: every prompt/code/library change should trigger golden dataset validation suite
- Edge cases flagged as commonly missed: regional/geographic bias, adversarial prompts, prompt injection

### Key Discussion Point — 63% Relevance Score

- 6 business users scored similar-ticket output at avg 63% relevance (amber)
- Product owner wants to ship anyway — Ishi pushed back
  - 63% means \~2 of 5 retrieved tickets are useful; not acceptable for a ticketing context
  - Recommended minimum: 75–80% relevance before shipping
  - Suggested fixes: prompt tuning or revisiting embedding/chunking strategy in the RAG

### Next Steps

- Oliver

  - Submit feedback on both candidates (Ishi + first candidate) to Josh — by tomorrow
  - Both candidates recommended to proceed; initiate feedback/offer process for both

- Ishi

  - Current project wraps Thursday (this week)
  - Available to start early next week

---

Chat with meeting transcript: [https://notes.granola.ai/t/5516cb23-a376-4e27-b61b-9df07af0f9d4](https://notes.granola.ai/t/5516cb23-a376-4e27-b61b-9df07af0f9d4)
