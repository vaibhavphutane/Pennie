# WriteDock

A native macOS writing assistant with explicit selected-text capture, a source/suggestion preview, and configurable OpenRouter and LiteLLM Inference Hub backends. The desktop UI and editing integration run locally; the selected backend performs inference. This is an independent implementation, with no Grammarly code or assets in the application.

## Run

Build from a fresh clone, then open the app:

```bash
bash scripts/build-app.sh
open dist/WriteDock.app
```

Build outputs in `dist/` are local artifacts and are not committed. If you already have the local build, open `dist/WriteDock.app` directly.

For a stable installation, copy the app to `~/Applications` or `/Applications` **before** granting Accessibility permission. In WriteDock Settings, choose **Enable Accessibility…**, then enable that exact app in **System Settings → Privacy & Security → Accessibility**. Quit and reopen WriteDock if macOS does not recognize the change. The local build is ad-hoc signed; rebuilding can require removing and re-adding its Accessibility entry. A developer signing identity provides a more stable identity across updates.

The build was compiled and launched on macOS 26.7.1 arm64. Deployment target is macOS 13; other macOS versions and Intel have not been validated. This is a local build, not a notarized distribution.

## Configure inference

Open **Settings** (`⌘,`). Each backend retains its own URL/model and Keychain credential. Select the active backend, fill in its settings, and press **Save settings & key**. Switching the active backend requires no restart or code change.

| Setting | OpenRouter | LiteLLM Inference Hub |
|---|---|---|
| API base URL | `https://openrouter.ai/api/v1` | Your gateway's exact API prefix, often `https://your-host/v1`; root prefixes also work |
| API key | Your OpenRouter key | Your LiteLLM virtual key or gateway-issued key |
| Model ID | Exact ID available to your OpenRouter account | Exact model/deployment alias exposed by your gateway |

Do not append `/chat/completions`; WriteDock appends it. Model fields intentionally start empty rather than assuming entitlement to a model. Ask your gateway administrator for the LiteLLM URL and alias. The app uses `POST {baseURL}/chat/completions` with bearer authentication and ordinary non-streaming chat messages. See [OpenRouter's API reference](https://openrouter.ai/docs/api_reference/overview) and [LiteLLM client configuration](https://docs.litellm.ai/docs/proxy/user_keys).

Keys are saved only in macOS Keychain, bound to the backend **and exact base URL**. Changing a URL requires saving a key for that URL; credentials are never automatically carried to another endpoint. A blank key field preserves the existing key. **Remove saved key** removes the credential for the currently displayed backend/URL. Keys for other saved URLs can be removed by selecting that URL and using this action, or through Keychain Access under service `local.WriteDock.backend`.

URLs require HTTPS, except exact loopback hosts for local gateways. Redirects are refused, and authentication/rate-limit/model/unavailable/timeout errors leave source text unchanged. No automatic retries or fallback to another backend occur. A local unauthenticated proxy may use a non-secret placeholder key if it ignores authorization; the current client requires a nonempty field.

## Use

1. Select a passage in Outlook, Teams, or Slack. Press **⌘⇧G**, or use the WriteDock menu bar's capture action. The app must be enabled in Settings.
2. Review the **Text to send**. Edit or redact it if needed. Choose grammar/spelling/punctuation, clarity, brevity, professional tone, or conversational tone.
3. Confirm the displayed destination and model, then press **Send**. This is the only action that submits writing text for inference.
4. Review the side-by-side suggestion. **Accept** approves it locally; **Replace selection** performs a separately requested, verified edit. **Dismiss** discards the suggestion. **Copy** places the suggestion on your clipboard.

If you edit the captured preview, WriteDock disables automatic replacement because that preview no longer matches the source selection. Use Copy instead. Accept does not submit or change a message in another app. WriteDock never sends mail or chat messages.

For editors that omit AX text/range attributes or refuse writable selections, copy the desired passage yourself, use **Paste text**, request a suggestion, and copy/paste the result back. Check the selection and formatting before pasting. This fallback also works without Accessibility permission.

The preview opens near the selection when the editor supplies bounds. This version has no continuous underlines, automatic background suggestions, or per-word inline accept bubbles. It does not install Outlook/Teams/Slack add-ins. Automatic replacement requires a single selection, unchanged focus/text/range, writable AX selection, and bounded readable context. It never overwrites the entire field. Rich style runs inside the replaced selection may change; formatting fidelity in the three target apps remains to be manually verified.

## Privacy and limits

- Capture happens only on shortcut/menu invocation, in an allowed app and eligible editable field. Secure/protected fields are rejected. There is no typing monitor, background text upload, or persistent text history.
- Only the preview passage, chosen action, writing preferences, and model request fields go to the selected endpoint. Your provider's own retention policies still apply.
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
dist/WriteDock.app/Contents/MacOS/WriteDock --diagnostics
```

The build script creates and verifies an ad-hoc signature. Set `WRITEDOCK_SIGNING_IDENTITY` to your own signing identity to sign with it. Full Xcode environments can also run `swift test`; this machine's Command Line Tools lack XCTest, so the dependency-free test harness is the validated route.

For a no-cost local demo:

```bash
python3 scripts/mock_backend.py
```

Choose LiteLLM, base URL `http://127.0.0.1:8765/v1`, model `mock-editor`, key `local-test`. The mock returns deterministic fixture edits, **not actual AI inference**. Try `This are a example. I has recieved teh message.` Stop the server with Ctrl-C. Restore your real provider settings when finished.

See [validation results and the manual test matrix](docs/VALIDATION.md), [the reverse-engineering report](docs/REVERSE_ENGINEERING.md), and [the detailed static evidence ledger](docs/static-findings.md). Live provider calls and cross-app capture/replacement remain pending credentials and Accessibility permission; automated mock results do not establish those outcomes.

Raw third-party inspection output and machine-specific runtime inventories stay local. The published repository includes the findings and test summaries; [evidence availability](docs/evidence/README.md) describes the distinction.
