# Pennie

<img src="Sources/Pennie/Resources/Pennie.png" alt="Pennie, a mint-colored writing companion with a fountain-pen crest" width="128">

**Say it like you.**

Your writing companion, powered by the model you choose. No extra writing subscription.

Pennie brings grammar fixes, clearer sentences, rewrites, and tone adjustments to your Mac—the everyday writing tasks. Connect your own model through **OpenRouter, OpenAI, LiteLLM Inference Hub, Claude (Anthropic), or another compatible API gateway**.

Use the model access you already have. Pennie adds no subscription of its own: you supply the endpoint, model, and API key. Your provider's API usage charges and access requirements still apply; check whether your existing plan includes API access.

The app runs locally and sends the text you choose directly to your configured endpoint. **There is no Pennie cloud service in between.** You control what to send, which model receives it, and whether to apply the result.

## Meet Pennie

Pennie is your familiar desk companion—the favorite pen you reach for when you want the words to come out right. Bring your thoughts. Pennie helps you shape them into writing that still sounds like you.

The mint companion beside your editor and the app in your Dock share the same name: **Pennie**. Quiet, patient, and ready when you are, Pennie offers a second look at your words. You choose what to keep.

## Writing help where you work

Pennie appears beside supported editors in Outlook, Teams, and Slack. Click Pennie to load the draft from your text box, ask for help, and accept the suggestion to update that same box. Select a passage first when you only want to edit part of the draft. You can also paste text into the full editor and copy the result back into any app.

The compact companion and full editor offer the same **16 writing actions**:

| What you need | What Pennie can do |
| --- | --- |
| Polish a draft | Fix grammar, spelling, and punctuation; improve writing; rephrase; improve clarity; shorten or expand |
| Find the right tone | Make writing professional, conversational, confident, empathetic, or persuasive |
| Reshape your text | Summarize, turn prose into bullet points, translate into a language you choose, or follow a custom editing request |
| Understand how it reads | Get a tone report with supporting examples and reader-impact guidance |

Set your preferred English dialect, audience, formality, and personal dictionary in **Settings → Writing goals & personal dictionary**. American, British, Australian, and Canadian English are supported as model instructions. Your chosen action takes precedence over conflicting defaults.

## Get started

Build from a fresh clone on macOS with Apple's Command Line Tools installed:

```bash
bash scripts/build-app.sh
open dist/Pennie.app
```

For regular use, copy the app to `~/Applications` or `/Applications` **before** granting Accessibility permission. Open **Settings** (`⌘,`), choose **Enable Accessibility…**, and enable that exact app in **System Settings → Privacy & Security → Accessibility**. Quit and reopen Pennie if needed. Manual copy/paste works without this permission.

Next, connect your model below and open Pennie from a text box to try your first edit.

## Bring your own model

Choose the provider or gateway that fits your workflow: a personal API account, your organization's inference hub, or a local model server with a compatible API. You can change providers and models in Settings without restarting the app or changing code.

| Provider or gateway | Select in Settings | API base URL | API used |
| --- | --- | --- | --- |
| OpenRouter | OpenRouter | `https://openrouter.ai/api/v1` | Chat Completions |
| OpenAI | OpenAI | `https://api.openai.com/v1` | Responses |
| LiteLLM Inference Hub | LiteLLM Inference Hub | Your gateway's API prefix | Chat Completions |
| Claude (Anthropic) | Claude (Anthropic) | `https://api.anthropic.com/v1` | Messages |
| Another compatible gateway or local server | LiteLLM Inference Hub | Your endpoint's API prefix, such as `https://your-gateway/v1` | Chat Completions |

For another gateway, use **LiteLLM Inference Hub** when it accepts OpenAI-compatible Chat Completions requests with bearer-key authentication. This setting does not require the gateway to run LiteLLM. Compatibility depends on the endpoint and model supporting the request and response format; a configurable URL alone does not make every gateway compatible.

1. Open **Settings** (`⌘,`) and select a backend.
2. Enter its **API base URL** and the exact **Model ID** or deployment alias available to your account. Model fields start empty so you can choose your own.
3. Use **Paste key**, then **Save settings & key**. Each backend keeps its own URL and model; credentials are stored in macOS Keychain for that backend and exact URL.
4. Optionally choose **Test correction with sample text** to check the connection. This sends the displayed synthetic sentence using your provider's quota, with no draft or personal writing preferences.

Enter the API prefix only. Pennie appends `/chat/completions`, `/responses`, or `/messages` for the selected backend. Remote endpoints require HTTPS; exact loopback hosts such as `localhost` and `127.0.0.1` may use HTTP. A local server that ignores authentication can use a non-secret placeholder key; the client requires a nonempty key.

Saving confirms local storage, not successful provider authentication. Save a newly pasted key before testing. Existing OpenRouter/LiteLLM settings migrate without resetting their values.

## Your text goes to the provider you choose

Pennie's interface, text capture, and suggestion review run on your Mac. Inference runs at the endpoint you configure. Using a remote provider means sending that provider the passage you submit; using a gateway may also involve the upstream model provider it routes to. Their processing and retention policies apply. A local endpoint keeps inference on your Mac only if the server also runs the model locally without forwarding requests.

- **You decide when text is sent.** Capturing a passage or selecting an action in the picker does not upload it. Review or redact **Your words**, confirm the destination and model, then press the task button, such as **Fix grammar**. **Regenerate** explicitly sends another request.
- **The request contains the passage and editing instructions.** These include the selected action, applicable custom request or translation language, writing goals, personal dictionary, preferences, and model request fields. No tools or conversation history are sent. Direct OpenAI requests set `store: false`; provider retention policies still apply.
- **No background draft uploads or persistent writing history.** Pennie tracks editor metadata and bounds to position itself without reading the text during tracking. Text capture happens only when you click Pennie or invoke capture. Secure and protected fields are rejected.
- **Your API keys are stored in macOS Keychain.** They are sent only to the configured endpoint for authentication. Credentials are scoped to the backend and exact URL, cached in memory until Quit, and never written to preferences, logs, or writing history. Changing the endpoint does not reuse another endpoint's key.
- **Requests stay under your control.** Redirects are refused. Pennie does not automatically retry or fall back to another backend. Failed inference requests leave the source text unchanged.

Non-secret settings are stored locally in macOS UserDefaults. Source context used to verify a replacement stays in memory and is never sent to the model. See [current limits](#current-limits) for capture and replacement details.

## Make your first edit

1. **Capture.** Click the text box in Outlook, Teams, or Slack, then click Pennie. Your existing draft loads automatically. Select a passage first to edit only that part. Press **⌘⇧G** to capture the draft or selection into the full editor, or use **Paste text** for text you copied yourself.
2. **Choose.** Review **Your words** and pick a **Writing action**, such as Grammar & spelling, Make concise, or Professional tone.
3. **Ask Pennie.** Check the displayed endpoint and model, then press the button for your task: **Fix grammar**, **Make concise**, **Make professional**, or another selected action. This sends the request to your configured model.
4. **Review.** Read the result. **Show changes** highlights additions in green and removals with red strikethrough. Copy and Accept use the clean result.
5. **Apply.** Choose **Accept** to update the original text box directly. Pennie rechecks the source and verifies the edit. If you captured a selection, only that passage is replaced. **Copy** lets you paste the result yourself; **Dismiss** discards the suggestion.

Accept applies the suggestion in one step when the preview is still linked to its source text box. For pasted or edited previews, use Copy to move the result into your app. Pennie never sends mail or chat messages. Tone insights are a separate report and cannot be accepted or used as replacement text.

If you edit or redact the captured preview, direct replacement is disabled because it no longer matches the original selection. Use Copy instead. Clicking Pennie with no selection captures the whole readable draft for direct replacement. Editors that do not expose a supported write method use the manual copy/paste workflow.

## Settings and troubleshooting

<details>
<summary>Saved keys and macOS authorization</summary>

The key box clears after saving. **API key saved in Keychain for this backend and URL** confirms storage. A blank key field keeps the saved key; **Remove saved key** deletes it and clears that endpoint's session cache. To remove a key for another URL, select that URL first, or use Keychain Access under service `local.WriteDock.backend`.

Corrections and Settings status checks use noninteractive Keychain queries. If access needs approval, choose **Unlock saved key** or paste and save the key again. Saving, removing, or explicitly unlocking a key may trigger macOS authorization. **Always Allow** trusts the current signed build for subsequent launches; a locked Keychain or a newly signed build can require approval again. Pennie does not weaken Keychain access controls.

</details>

<details>
<summary>Pennie placement, visibility, and Accessibility</summary>

Pennie appears beside detected editors, with a lower-right corner launcher when editor detection or Accessibility is unavailable. It stays within the visible display, including additional monitors. A corner launcher does not bypass protected-field checks or grant text access.

Pennie checks foreground editor metadata about every 0.7 seconds while enabled. Its nonactivating panel keeps the source app active. Closing the compact preview or switching apps/fields clears it. **Open editor** moves the preview into the larger window. Backend, model, or preference changes invalidate pending suggestions.

Use **Pause here** to hide Pennie in one app and resume it in Settings. Disabled, paused, and disallowed apps hide the widget. You can turn the widget or character animation off; system Reduce Motion is respected.

Settings shows Pennie's own Accessibility state and widget status. Permission granted to another app does not apply to Pennie. If macOS shows Pennie enabled but access is denied, remove and re-add the current app bundle, authenticate if asked, then reopen it. Rebuilding an ad-hoc-signed app can require renewing its grant. A stable developer signing identity helps preserve trust across updates.

</details>

<details>
<summary>Unchanged text or an unexpected result</summary>

Pennie labels identical output **UNCHANGED TEXT** and disables Accept. Grammar checks may correctly leave clean text alone. Choose **Improve writing** or **Rephrase** when you want a different version. An echo from a rewrite action is reported as incomplete; try **Regenerate** or another model.

Use **Test correction with sample text** in Settings to check the selected backend. Missing keys, missing model IDs, authentication failures, rate limits, unavailable models, and timeouts are reported explicitly. A saved key alone does not confirm a working connection.

</details>

## Build and verify

No third-party application dependencies are required. Install Apple's Command Line Tools if `swift` is absent. Build outputs in `dist/` are local artifacts and are not committed.

```bash
bash scripts/build-app.sh
bash scripts/test-core.sh
bash scripts/test-loopback.sh
bash scripts/test-accessibility.sh
bash scripts/test-widget.sh
dist/Pennie.app/Contents/MacOS/Pennie --check-widget-state
dist/Pennie.app/Contents/MacOS/Pennie --diagnostics
```

The build script creates and verifies an ad-hoc signature. Set `PENNIE_SIGNING_IDENTITY` to your own signing identity to sign with it, or `PENNIE_APP_DIR` to choose the output path. The earlier `WRITEDOCK_SIGNING_IDENTITY` and `WRITEDOCK_APP_DIR` variables remain supported. Full Xcode environments can also run `swift test`; the standalone scripts provide a dependency-free test harness when Command Line Tools lack XCTest.

Pennie was previously called WriteDock. The bundle identifier and Keychain service retain their original identifiers so existing preferences and saved keys remain accessible. Build and open `dist/Pennie.app` for the updated app; quit the earlier app before switching. A rebuilt ad-hoc-signed app can still require renewed macOS authorization.

The build was compiled and launched on macOS 26.7.1 arm64. Deployment target is macOS 13; other macOS versions and Intel have not been validated. This is a local build, not a notarized distribution.

Preview Pennie without Accessibility permission or inference using `dist/Pennie.app/Contents/MacOS/Pennie --widget-demo`. This is a disabled, synthetic UI demonstration. Pennie artwork is bundled with the application and used for its Finder, Dock, and About icon.

See [the testing guide](docs/VALIDATION.md) for automated checks, Keychain checks, and the manual application integration checklist. To deliberately run all 16 synthetic live backend checks (uses API quota; never captures application text):

```bash
dist/Pennie.app/Contents/MacOS/Pennie --check-configured-backend
```

### Try the workflow without API usage

Start the local mock server:

```bash
python3 scripts/mock_backend.py
```

Choose **LiteLLM Inference Hub**, base URL `http://127.0.0.1:8765/v1`, model `mock-editor`, and key `local-test`. Try `This are a example. I has recieved teh message.` The mock returns deterministic fixture edits, **not actual AI inference**. Stop it with Ctrl-C and restore your real provider settings when finished.

## Current limits

- Suggestions depend on the selected model and need review. Writing goals and dictionary entries are model instructions, not a guaranteed local spelling engine. Truncated, refused, empty, malformed, or unavailable responses are reported without applying them.
- Passages are limited to 12,000 UTF-16 characters. A source field's Accessibility value is read to check staleness; at most 12,000 UTF-16 characters of context are retained in memory. Larger or inaccessible context makes direct replacement unavailable.
- Direct replacement requires the original text box, unchanged text and selection/caret, and enough readable context to verify the edit. A captured selection is replaced through a writable Accessibility selection. A captured whole draft is selected and replaced, or written through the field’s Accessibility value when selection writes are unavailable. Pennie verifies the resulting text and caret and never retries an uncertain write. Rich formatting in replaced text may change; review it afterward. Copy deliberately replaces clipboard contents.
- Pennie provides writing help on request. Continuous underlines, background suggestions, per-word accept bubbles, plagiarism checking, AI-text detection, authorship tracking, and learned style libraries are not included. It does not install Outlook, Teams, or Slack add-ins.

For contributors, the [Pennie identity guide](docs/BRAND.md) defines the shared name, character story, and product voice.
