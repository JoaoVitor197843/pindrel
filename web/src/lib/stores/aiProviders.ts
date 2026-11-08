export interface AiProvider {
  id: string
  label: string
  /** Runs on the person's own machine or network: it takes an address, not a key. */
  local: boolean
  placeholder: string
}

/** The providers the settings offer. Nothing is sent anywhere yet: the section is a prototype. */
export const AI_PROVIDERS: AiProvider[] = [
  { id: 'anthropic', label: 'Anthropic (Claude)', local: false, placeholder: 'sk-ant-…' },
  { id: 'openai', label: 'OpenAI', local: false, placeholder: 'sk-…' },
  { id: 'google', label: 'Google (Gemini)', local: false, placeholder: 'AIza…' },
  { id: 'mistral', label: 'Mistral', local: false, placeholder: 'chave da Mistral' },
  { id: 'groq', label: 'Groq', local: false, placeholder: 'gsk_…' },
  { id: 'deepseek', label: 'DeepSeek', local: false, placeholder: 'sk-…' },
  { id: 'xai', label: 'xAI (Grok)', local: false, placeholder: 'xai-…' },
  { id: 'openrouter', label: 'OpenRouter', local: false, placeholder: 'sk-or-…' },
  { id: 'ollama', label: 'Endpoint local (Ollama)', local: true, placeholder: 'http://localhost:11434' },
  { id: 'compatible', label: 'Endpoint compatível com OpenAI (LM Studio, vLLM…)', local: true, placeholder: 'http://localhost:1234/v1' },
]
