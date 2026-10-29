# WriteDock

A native macOS writing assistant with **Nib**, a floating writing companion, a source/suggestion preview, and configurable OpenRouter, LiteLLM Inference Hub, OpenAI, and Claude (Anthropic) backends. The desktop UI and editing integration run locally; the selected backend performs inference.

## Run

Build from a fresh clone, then open the app:

```bash
bash scripts/build-app.sh
open dist/WriteDock.app
```

Build outputs in `dist/` are local artifacts and are not committed. If you already have the local build, open `dist/WriteDock.app` directly.

For a stable installation, copy the app to `~/Applications` or `/Applications` **before** granting Accessibility permission. In WriteDock Settings, choose **Enable Accessibility…**, then enable that exact app in **System Settings → Privacy & Security → Accessibility**. Quit and reopen WriteDock if macOS does not recognize the change. The app includes Nib as its Finder/Dock/About icon. The local build is ad-hoc signed; rebuilding can require removing and re-adding its Accessibility entry. A developer signing identity provides a more stable identity across updates.

The build was compiled and launched on macOS 26.7.1 arm64. Deployment target is macOS 13; other macOS versions and Intel have not been validated. This is a local build, not a notarized distribution.

## Configure inference

Open **Settings** (`⌘,`). Each backend retains its own URL/model and Keychain credential. Select the active backend, fill in its settings, and press **Save settings & key**. Switching the active backend requires no restart or code change.

The API-key box has a visible border and a **Paste key** button. Paste into that box, then save. The box clears after saving; **API key saved in Keychain for this backend and URL** confirms local storage. A missing key or Model ID is called out explicitly. Saving does not make a network request or validate provider authentication.

| Backend | Default API base URL | Model |
|---|---|---|
| OpenRouter | `https://openrouter.ai/api/v1` | Exact OpenRouter model ID |
| LiteLLM Inference Hub | Your gateway's API prefix | Exact deployment alias |
| OpenAI | `https://api.openai.com/v1` | Exact OpenAI model ID available to your API project |
| Claude (Anthropic) | `https://api.anthropic.com/v1` | Exact Claude model ID available to your API account |

Enter the API prefix only. WriteDock appends `/chat/completions` for OpenRouter/LiteLLM, `/responses` for OpenAI, or `/messages` for Claude. Direct OpenAI requests set `store: false`; Claude uses `x-api-key` and the pinned `anthropic-version: 2026-10-21`. No tools or conversation history are sent. See the [OpenAI text-generation guide](https://developers.openai.com/api/docs/guides/text) and [Claude Messages reference](https://platform.claude.com/docs/en/api/messages/create). Model fields start empty so you can choose an ID enabled for your account. Existing OpenRouter/LiteLLM settings migrate without resetting their values.

Keys are saved only in macOS Keychain, separately for each backend **and exact base URL**. A saved or unlocked key is cached in this process until Quit, so repeated corrections do not repeatedly read Keychain. Changing providers/URLs never reuses another endpoint's key. No keys enter preferences, logs, source files, or writing history.

Corrections and Settings status checks use noninteractive Keychain queries. If macOS cannot authorize a saved key, WriteDock shows guidance instead of opening a password dialog automatically. Choose **Unlock saved key** in Settings to approve that read once, or paste the key again and choose **Save settings & key**. The native authorization dialog offers **Always Allow** to trust the current signed build for subsequent launches. Saving/removing a key and explicitly unlocking it may still need macOS authorization. A locked login Keychain or a newly signed build can require approval again. The build script supports `WRITEDOCK_SIGNING_IDENTITY` for a stable developer identity; ad-hoc signing changes trust across rebuilds. The app does not weaken Keychain access controls to avoid prompts.

A blank key field keeps the saved key. **Remove saved key** also clears that endpoint's session cache. Keys for other URLs can be removed by selecting that URL and using this action, or through Keychain Access under service `local.WriteDock.backend`.

URLs require HTTPS, except exact loopback hosts for local gateways. Redirects are refused, and authentication/rate-limit/model/unavailable/timeout errors leave source text unchanged. No automatic retries or fallback to another backend occur. A local unauthenticated proxy may use a non-secret placeholder key if it ignores authorization; the current client requires a nonempty field.

## Use

1. Switch to Outlook, Teams, or Slack. **Nib appears beside a detected editor**, or in the lower-right corner of the display when editor detection or Accessibility is unavailable. Select a passage and click Nib to open the compact writing panel. **⌘⇧G** still opens the full editor.
2. Review the **Text to send**. Edit or redact it if needed. Choose an option from **Writing action** in Nib or the full editor.
3. Confirm the displayed destination and model, then press **Send**. Choosing an action alone does not send anything. **Regenerate** explicitly sends another request with the same passage and action.
4. Review the result. **Show changes** marks additions in green and removals with red strikethrough; Copy/Replace always use the clean result. **Accept** approves it locally; **Replace selection** performs a separately requested, verified edit. **Dismiss** discards the suggestion. **Copy** places the suggestion on your clipboard.

Both interfaces expose the same **16 actions**:

- **Polish & rewrite:** grammar/spelling/punctuation, improve writing, rephrase, clarity, brevity, expand.
- **Tone:** professional, conversational, confident, empathetic, persuasive.
- **Transform:** summarize, bullet points, translate into an explicitly entered language, custom editing request.
- **Understand:** tone insights, returned as a separate report with evidence and reader-impact guidance. Reports cannot be accepted or used as replacement text.

**Settings → Writing goals & personal dictionary** offers American, British, Australian, and Canadian English, audience, default formality, and accepted terminology. These are model instructions, not a guaranteed local spelling engine. The selected action takes precedence over conflicting defaults.

If the result is unchanged, WriteDock labels it **UNCHANGED TEXT** and disables Accept/Replace. Grammar can correctly leave clean text alone; use **Improve writing** or **Rephrase** when you want a different version. An echo from a rewrite action is reported as an incomplete action, not a successful improvement. Try Regenerate or another model. **Settings → Test correction with sample text** checks the current backend using a displayed, synthetic sentence and your account's quota; it sends no draft or personal preferences. Save a newly pasted key before testing.

With no selection, clicking Nib previews the draft if the editor exposes a readable value and an empty selection range. This mode supports Copy; select text first for direct replacement. If you edit the captured preview, WriteDock disables automatic replacement because that preview no longer matches the source selection. Use Copy instead. Accept does not submit or change a message in another app. WriteDock never sends mail or chat messages.

Nib uses a nonactivating floating panel so opening it does not activate WriteDock over the source app. Close clears the compact preview; switching fields/apps also clears it. **Pause here** hides Nib for that app; resume it in Settings. You can turn the widget or character animation off, and system Reduce Motion is respected. **Open editor** moves the current preview into the larger window. Backend/model/preference changes invalidate pending suggestions in either view.

For editors that omit AX text/range attributes or refuse writable selections, copy the desired passage yourself, use **Paste text**, request a suggestion, and copy/paste the result back. Check the selection and formatting before pasting. This fallback also works without Accessibility permission.

Nib follows field bounds and stays within the visible display, including additional monitors. An unavailable, protected, or offscreen editor uses a generic corner launcher in allowed apps; this never bypasses protected-field checks or grants text access. Disabled, paused, and disallowed apps hide Nib. Settings shows WriteDock's own Accessibility state and the widget's current status. Access granted to another app does not grant it to WriteDock. If macOS shows WriteDock enabled but the app reports access denied, remove and re-add the current app bundle, authenticate if macOS asks, then reopen WriteDock.

This version has no continuous underlines, automatic background suggestions, or per-word inline accept bubbles. It does not install Outlook/Teams/Slack add-ins. Automatic replacement requires a single selection, unchanged focus/text/range, writable AX selection, and bounded readable context. It never overwrites the entire field. Review formatting after replacement; rich style runs inside a replacement may change.

## Privacy and limits

- While enabled, Nib checks foreground editor metadata and bounds about every 0.7 seconds; it does not read field values or selected text during this tracking. Text capture happens only on a widget click or shortcut/menu invocation. Secure/protected fields are rejected. There is no typing monitor, background text upload, or persistent text history.
- Only the preview passage, chosen action, custom request or translation language, writing goals, personal dictionary, writing preferences, and model request fields go to the selected endpoint. Your provider's own retention policies still apply.
- Up to 12,000 UTF-16 characters are accepted. A source field's AX value is read to check staleness; at most 12,000 UTF-16 characters of context are retained in memory and that context is never sent. Larger or inaccessible context makes replacement unavailable.
- Suggestions are model-generated and need review. Long/truncated, refused, empty, malformed, or unavailable responses are reported without applying them.
- Copy deliberately replaces clipboard contents. Manual paste and formatting are under your control. Credentials and text are not logged by WriteDock; non-secret settings use macOS UserDefaults.

## Build and verify

No third-party application dependencies are required. Install Apple's Command Line Tools if `swift` is absent.

```bash
bash scripts/build-app.sh
bash scripts/test-core.sh
bash scripts/test-loopback.sh
bash scripts/test-accessibility.sh
bash scripts/test-widget.sh
dist/WriteDock.app/Contents/MacOS/WriteDock --check-widget-state
dist/WriteDock.app/Contents/MacOS/WriteDock --diagnostics
```

The build script creates and verifies an ad-hoc signature. Set `WRITEDOCK_SIGNING_IDENTITY` to your own signing identity to sign with it. Full Xcode environments can also run `swift test`; this machine's Command Line Tools lack XCTest, so the dependency-free test harness is the validated route.

Preview Nib without Accessibility permission or inference using `dist/WriteDock.app/Contents/MacOS/WriteDock --widget-demo`. This is a disabled, synthetic UI demonstration, not a Slack integration test. Nib artwork is bundled with the application and used for its icon.

For a no-cost local demo:

```bash
python3 scripts/mock_backend.py
```

Choose LiteLLM, base URL `http://127.0.0.1:8765/v1`, model `mock-editor`, key `local-test`. The mock returns deterministic fixture edits, **not actual AI inference**. Try `This are a example. I has recieved teh message.` Stop the server with Ctrl-C. Restore your real provider settings when finished.

See [the testing guide](docs/VALIDATION.md) for automated checks and the manual integration checklist.

To deliberately repeat the 16 synthetic live backend checks (uses API quota; never captures application text):

```bash
dist/WriteDock.app/Contents/MacOS/WriteDock --check-configured-backend
```

Plagiarism checking, AI-text detection, authorship tracking, learned style libraries, and automatic underlines are not included.
