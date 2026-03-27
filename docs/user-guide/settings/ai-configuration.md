# AI Configuration

Configure AI providers for Document Chat, Vault Chat, and the Dashboard AI Briefing. Open via **Quartz Notes > Settings > AI**.

## Adding a provider

1. Select a provider from the dropdown (OpenAI, Anthropic, Google, OpenRouter, or Ollama)
2. Enter your API key
3. Select a model
4. Click **Save**

## Supported providers

| Provider | API Key Source | Models |
|----------|---------------|--------|
| **OpenAI** | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) | GPT-4o, GPT-4 Turbo, GPT-3.5 Turbo |
| **Anthropic** | [console.anthropic.com](https://console.anthropic.com) | Claude Opus 4, Claude Sonnet 4, Claude Haiku |
| **Google** | [aistudio.google.com](https://aistudio.google.com) | Gemini Pro, Gemini Ultra |
| **OpenRouter** | [openrouter.ai](https://openrouter.ai) | Any model available on OpenRouter |
| **Ollama** | Local (no key needed) | Any locally running Ollama model |

## Ollama (local AI)

For fully private, offline AI:

1. Install [Ollama](https://ollama.ai) on your Mac
2. Pull a model: `ollama pull llama3`
3. In Quartz Notes AI settings, select **Ollama** as provider
4. The base URL defaults to `http://localhost:11434`

No API key is needed. Everything runs on your Mac.

## Privacy and security

- API keys are stored in the macOS Keychain (encrypted, per-user)
- Quartz Notes never transmits your keys to any server other than your chosen provider
- Only the minimum necessary context is sent (current note for Document Chat, relevant chunks for Vault Chat)
- No telemetry, analytics, or usage data is collected

## Cost considerations

AI providers charge per token. Typical costs:

- **Document Chat** message: ~1,000-5,000 tokens ($0.001-$0.01)
- **Vault Chat** query: ~3,000-10,000 tokens ($0.003-$0.03)
- **AI Briefing**: ~5,000-15,000 tokens ($0.005-$0.05)

Using Ollama is completely free (runs locally).

---

**Next:** [All Keyboard Shortcuts](../keyboard-shortcuts/all-shortcuts.md)
