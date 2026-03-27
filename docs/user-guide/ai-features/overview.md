# AI Features Overview

Quartz Notes offers AI assistance at three tiers — all privacy-first, with no data leaving your device unless you explicitly configure a cloud provider.

## Tiered AI architecture

| Tier | Provider | Cost | Privacy |
|------|----------|------|---------|
| **System** | Apple Writing Tools | Free | On-device |
| **On-device** | Foundation Models | Free | On-device |
| **Cloud** | Your API key | Pay-per-use | Your provider's terms |

## Apple Writing Tools (Free, built-in)

On macOS 15.1+, Apple's Writing Tools are available directly in the editor:
- **Rewrite** — Rephrase text in different tones
- **Proofread** — Fix grammar and spelling
- **Summarize** — Condense selected text

Access via right-click > Writing Tools, or through the system keyboard shortcut.

## Document Chat

Chat with AI about the note you're currently editing. The AI reads your note's content and can answer questions, suggest improvements, or help brainstorm ideas.

## Vault Chat (RAG)

Ask questions across your entire vault. Quartz Notes uses on-device vector embeddings to find relevant notes and provides answers with source citations.

## Configuring AI providers

Go to **Settings > AI** to add your API keys:

| Provider | Models |
|----------|--------|
| OpenAI | GPT-4o, GPT-4 Turbo |
| Anthropic | Claude 3.5 Sonnet, Claude 3 Opus |
| Google | Gemini Pro, Gemini Ultra |
| OpenRouter | Any model via OpenRouter |
| Ollama | Local models (Llama, Mistral, etc.) |

Your API keys are stored locally in Keychain. Quartz Notes never stores or transmits your keys to any server other than the provider you choose.

---

**Next:** [Document Chat](document-chat.md)
