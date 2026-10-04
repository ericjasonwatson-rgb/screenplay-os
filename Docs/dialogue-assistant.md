# Optional dialogue assistant

AI > Connect AI provider opens local setup for OpenAI or Anthropic. Paste your own API key, Load models, choose a text-generation model, then Test & Connect. The test asks for three imaginary greetings, without screenplay content. It can incur API charges. A successful test saves the key in macOS Keychain and the provider/model preference in local preferences, never in a screenplay. Disconnect removes the saved key on this Mac; revoke it with the provider to invalidate it elsewhere.

AI > Suggest dialogue line requires a selected dialogue paragraph in the full editor. The panel previews exactly the excerpt supplied as context: the speaker, selected line (up to 2,000 characters), and up to ten nearby paragraphs (up to 1,000 characters each), confined to that scene. The optional writer direction is limited to 1,000 characters. A fixed system instruction requests three dialogue alternatives. No request is sent until the user presses Send context & suggest three lines. Providers apply their own data policies; OpenAI requests set store=false, which is not a promise of zero retention.

Results remain transient until Replace or Insert after is selected. Acceptance rejects changed screenplay contents or a different document. Both operations use the existing Undo and save machinery. No automatic changes, tools, external links, provider fallback, or network retries are performed. Closing or cancelling invalidates pending results. Setup and suggestions do not run during ordinary writing. The experimental writing-only package editor is not supported.

Networking uses fixed HTTPS provider endpoints, ephemeral sessions without URL cache/cookies, rejects redirects, and reports sanitized errors rather than provider bodies or credentials. API keys are held transiently during entry/request; saved copies use a non-synchronizing Keychain item. Models are loaded on explicit request; account lists can contain non-text models, so the connection test verifies text generation and expected output structure. Anthropic's first model-list page is shown; manual model ID entry remains available.

This first implementation uses API keys, not consumer ChatGPT/Claude sign-in. It does not bundle a shared key, provide billing, or claim a consumer subscription includes API usage. No credentials or live screenplay requests were used during automated development validation. Live provider generation and Keychain behavior require manual review with the user's account.

References checked October 4, 2026:
- https://developers.openai.com/api/docs/guides/text
- https://platform.claude.com/docs/en/api/messages/create
