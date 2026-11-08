/// A provider the settings offer (the same list as the web's `aiProviders.ts`). Nothing is sent anywhere yet.
class AiProvider {
  const AiProvider(this.id, this.label, this.placeholder, {this.local = false});
  final String id, label, placeholder;

  /// Runs on the person's own machine or network: it takes an address, not a key.
  final bool local;
}

const aiProviders = <AiProvider>[
  AiProvider('anthropic', 'Anthropic (Claude)', 'sk-ant-…'),
  AiProvider('openai', 'OpenAI', 'sk-…'),
  AiProvider('google', 'Google (Gemini)', 'AIza…'),
  AiProvider('mistral', 'Mistral', 'chave da Mistral'),
  AiProvider('groq', 'Groq', 'gsk_…'),
  AiProvider('deepseek', 'DeepSeek', 'sk-…'),
  AiProvider('xai', 'xAI (Grok)', 'xai-…'),
  AiProvider('openrouter', 'OpenRouter', 'sk-or-…'),
  AiProvider('ollama', 'Endpoint local (Ollama)', 'http://localhost:11434', local: true),
  AiProvider('compatible', 'Endpoint compatível com OpenAI (LM Studio, vLLM…)', 'http://localhost:1234/v1', local: true),
];
