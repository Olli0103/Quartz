# Vault Chat (RAG)

Vault Chat lets you ask questions across your entire vault. It uses Retrieval-Augmented Generation (RAG) to find relevant notes and generate answers with source citations.

## How it works

1. Your notes are indexed into vector embeddings (512-dimensional, on-device via Apple's NLEmbedding)
2. When you ask a question, the most relevant note chunks are retrieved
3. These chunks are sent as context to your AI provider alongside your question
4. The AI generates an answer with `[Source N]` citations linking back to specific notes

## Opening Vault Chat

- Press **Cmd+Shift+J**
- Or click **Vault Chat** in the sidebar / command palette

## Asking questions

Type natural language questions like:

- "What are my notes about project management?"
- "Summarize what I know about machine learning"
- "What meetings did I have last week?"
- "Find all my notes related to the Q1 budget"

## Citations

The AI's response includes numbered citations like `[Source 1]`, `[Source 2]`. Each citation links to the original note. Click a citation to navigate directly to that note in the editor.

## Indexing

Quartz Notes automatically indexes your vault for Vault Chat when you open it. The indexing progress is shown in the sidebar. Subsequent opens are faster because only changed notes are re-indexed.

## Requirements

- An AI provider configured in Settings (for generating answers)
- Indexing must be complete (the first time may take a few minutes for large vaults)

## Privacy

- Vector embeddings are generated **on-device** using Apple's NLEmbedding framework
- Only relevant text chunks (not your entire vault) are sent to the AI provider
- The embedding index is stored locally in your vault's `.quartzindex/` directory

---

**Next:** [Exporting Notes](../export/exporting-notes.md)
