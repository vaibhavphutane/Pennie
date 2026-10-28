# WriteDock validation

## Recorded results

Validated on macOS 26.7.1, build 25G241, Apple Silicon. Automated checks use synthetic text and local fixtures; they do not establish live OpenRouter/LiteLLM model quality or application-specific Accessibility behavior.

| Check | Result | Evidence |
| --- | --- | --- |
| Inference core: configuration, routing, Unicode, five actions, input limits, sanitized errors, cancellation, redirect policy | **84 checks passed** | [core-checks.txt](evidence/core-checks.txt) |
| Real URLSession requests to the loopback mock: both backends, five actions, exact model/auth headers, HTTP 401/429/404/503, malformed/truncated responses, redirect refusal | **28 checks passed** | [loopback-checks.txt](evidence/loopback-checks.txt) |
| Pure replacement guard: Unicode/grapheme boundaries, changed selected text, invalid/overflowing ranges | **12 checks passed** | [accessibility-checks.txt](evidence/accessibility-checks.txt) |
| Actual macOS Keychain temporary fixture: write/read, backend isolation, endpoint isolation, delete | **Passed**, fixture removed | [keychain-checks.txt](evidence/keychain-checks.txt) |
| Native release bundle | **Compiled, ad-hoc signed, signature verified, UI launched** | `dist/WriteDock.app` |
| XCTest suite | **Not run successfully:** the installed Command Line Tools do not include the XCTest module. The dependency-free harness above ran instead. | `Tests/WriteDockCoreTests/InferenceClientTests.swift` |
| Accessibility prerequisite | **Not granted to the diagnostic process:** `Accessibility trusted: false` | [app-diagnostics.txt](evidence/app-diagnostics.txt) |
| REA runtime observation of WriteDock's own window | **Blocked:** native provider reports `accessibility-denied` | Local `docs/evidence/rea-rea-runtime-requests-1-observe_native_ui.json`; see [evidence availability](evidence/README.md) |
| Live backend authentication and inference | **Not tested:** no real backend key/model was configured for this run. | No external inference requests made |

Repeat the automated checks from the repository root:

```sh
./scripts/test-core.sh
./scripts/test-loopback.sh
bash scripts/test-accessibility.sh
```

The second script starts a mock server on an OS-assigned loopback port and stops only its own child process. Both scripts write their result to the corresponding evidence text file and return a failing exit status if a check fails. Full Xcode installations can additionally run `swift test`.

The Accessibility harness verifies pure range planning, not cross-process editing. `--check-keychain` on the built executable can repeat the temporary fixture test without accessing configured provider credentials. An offscreen UI fixture was rendered in `evidence/app-preview.png`; compositor-backed controls are incomplete in that image, so it is not a faithful desktop screenshot or proof of visual correctness. Live UI interaction remains part of the manual checklist.

## Application matrix: manual checks still required

The following versions were detected running. **No row below is a passed live integration test.** Accessibility permission blocked capture and replacement verification in this environment. A successful mock inference request does not verify formatting, focus, selection, or cursor behavior in any of these applications.

| Application | Installed version | Capture and preview | Replace, formatting, cursor | Manual test surface |
| --- | --- | --- | --- | --- |
| Microsoft Outlook | 16.113.4 | Pending permission and manual test | Pending permission and manual test | New unsent message, recipient left blank, message body |
| Microsoft Teams | 26261.303.5165.1465 | Pending permission and manual test | Pending permission and manual test | Expanded compose box in a chat with yourself; leave unsent |
| Slack | 4.52.171 | Pending permission and manual test | Pending permission and manual test | Compose box in your own conversation; leave unsent |

Teams classic (`com.microsoft.teams`) was not installed. The current Teams bundle is `com.microsoft.teams2`.

## Prepare a local-only inference test

1. Start `python3 scripts/mock_backend.py` from the repository root and leave that terminal open. It listens only on `127.0.0.1:8765` and does not log requests, text, or credentials.
2. Open WriteDock Settings. Select **LiteLLM Inference Hub**, enter base URL `http://127.0.0.1:8765/v1`, model `mock-editor`, and test key `local-test`. Click **Save settings & key**. These values are fixture credentials, not a real service key.
3. Click **Enable Accessibility…** and grant the built WriteDock application access in macOS System Settings → Privacy & Security → Accessibility. Relaunch WriteDock if macOS requests it. Permission is tied to the executable/application identity; a grant to another terminal or build does not prove the delivered app has access.
4. Leave Outlook, Teams, and Slack enabled in the capture allowlist. Close Settings before testing.
5. Use only the synthetic passages below. **Do not press Send in Outlook, Teams, or Slack.** WriteDock’s **Send to…** button sends the reviewed passage to the local mock, not to a chat recipient.

The mock implements a few fixed substitutions; it is not a grammar engine or language model. Unmatched text is returned unchanged. This isolates capture, transport, preview, and replacement from model variability.

## Run this sequence in each application

Start with this exact plain-text sample in the unsent compose body:

```text
Before: keep this sentence.
This are a example. I has recieved teh message. 👩🏽‍💻

Café — 你好.
After: keep this sentence too.
```

Select only the second line and press **⌘⇧G**. Expected captured text is exactly that line, including the emoji, without the surrounding paragraphs. If the shortcut conflicts, use WriteDock’s menu-bar capture action. Record whether a preview appears near the selection; a centered preview is the fallback when selection bounds are unavailable.

Choose **Grammar & spelling**, review **TEXT TO SEND**, then press WriteDock’s **Send to…**. The mock should return:

```text
This is an example. I have received the message. 👩🏽‍💻
```

Check each stage separately:

| Stage | Expected behavior | What to record |
| --- | --- | --- |
| Capture | Exact selected text; source application and surrounding text unchanged | Exact match or capture error |
| Preview | Original and suggested text visible; original editor unchanged | Suggested text matches fixture |
| Accept | Marks the suggestion accepted without editing the source | No editor mutation |
| Replace selection | Rechecks original element, text, selection, and focus; applies one replacement where supported | Success, refusal, or uncertain-write message |
| Cursor | After verified replacement, caret is immediately after the replacement and focus is in the original compose box | Visible caret and active app |
| Surrounding text | Both “Before” and “After” lines and blank paragraph remain intact | Exact comparison |
| Dismiss | Clears the suggestion without changing the source | No editor mutation |
| Copy fallback | Copies suggestion; user reselects the intended source text and pastes manually | Paste and formatting inspected separately |

If automatic capture or replacement is unsupported, record that result and test **manual copy → Paste text in WriteDock → Send → Accept → Copy → manual paste**. That is a supported fallback, not an automatic-replacement pass. WriteDock does not use a whole-field overwrite to force unsupported editors to work.

## Formatting, selection, and focus cases

Repeat these in **each** application, using its own formatting toolbar rather than literal Markdown where available. Keep all drafts unsent.

| Case | Procedure | Expected or required observation |
| --- | --- | --- |
| Bold | Make `recieved` bold, then select the entire sample sentence and replace | Record whether `received` retains the intended bold style; inspect unchanged runs too. Mixed formatting preservation is unverified until observed. |
| Hyperlink | Add a link labeled `reference` targeting `https://example.com` before and then within the selected passage | Verify both label and destination, including links outside the replacement. Record any formatting loss inside the selection. |
| List | Put the sample sentence in a bulleted list item between two unchanged items | Verify list markers, indentation, item boundaries, and surrounding items. |
| Emoji and non-ASCII | Select a passage containing `👩🏽‍💻`, `Café`, and `你好`, spanning a paragraph break | Verify no broken emoji, missing characters, merged paragraphs, or offset drift. |
| Selection changed | Capture and obtain a suggestion; return to the source and select a different range; return to WriteDock and replace | Refuse stale replacement without changing either selection’s text. |
| Text changed | Capture and obtain a suggestion; edit the original paragraph before replacing | Refuse stale replacement; recapture to proceed. |
| Focus changed | Capture, then focus a different compose field/window in the same app before replacing | Refuse if the captured field is no longer focused. Switching to a different app alone may be restored by intentional activation of the original app; it must never write into the other app. |
| Redacted preview | Edit **TEXT TO SEND** before sending | Automatic replacement becomes unavailable; use Copy/manual paste for the edited passage. |
| Empty selection | Place a caret without selecting text, then capture | Explain that a selection is required; no inference request. |
| Large selection | Select more than 12,000 UTF-16 units | Reject with the size limit. Emoji can occupy multiple UTF-16 units. |
| Large surrounding field | Select a short passage in a compose field longer than 12,000 UTF-16 units | Capture may work; automatic replacement must use the manual fallback if bounded verification context is unavailable. |

The app verifies resulting plain text and caret position when the editor exposes the needed APIs. It cannot certify rich-text preservation from that readback alone. A formatting failure is a failed formatting check even if the text replacement reports success.

## Rewrites and backend switching

Test each action in the scratchpad and then a selected passage in each application where capture is available:

| Action | Input | Mock output |
| --- | --- | --- |
| Grammar & spelling | `This are a example.` | `This is an example.` |
| Improve clarity | `We waited due to the fact that it rained.` | `We waited because it rained.` |
| Make concise | `We work at this point in time in order to finish.` | `We work now to finish.` |
| Professional tone | `Hey team, please respond ASAP.` | `Hello team, please respond as soon as possible.` |
| Conversational tone | `Dear team, I would like to meet.` | `Hi team, I'd like to meet.` |

Configure **OpenRouter** with the same loopback URL, model, and test key, save, and repeat a suggestion. Switch back to **LiteLLM Inference Hub** and repeat without changing code or restarting. This verifies backend switching against a compatible mock; actual OpenRouter and Inference Hub connectivity still require their real URLs, exact model IDs, and keys.

## Failures, cancellation, and privacy controls

Every base URL has a separate Keychain entry. For each error fixture below, save `local-test` again for that exact URL and keep model `mock-editor`; otherwise a missing-key error will prevent the intended test.

| API base URL | Expected result |
| --- | --- |
| `http://127.0.0.1:8765/auth/v1` | Authentication error; no source edit |
| `http://127.0.0.1:8765/rate/v1` | Rate-limit message with five-second retry guidance; no automatic retry |
| `http://127.0.0.1:8765/model/v1` | Unavailable-model guidance |
| `http://127.0.0.1:8765/server/v1` | Service-unavailable guidance |
| `http://127.0.0.1:8765/malformed/v1` | Invalid-response message; no accepted suggestion |
| `http://127.0.0.1:8765/truncated/v1` | Incomplete output rejected rather than offered for replacement |
| `http://127.0.0.1:8765/redirect/v1` | Redirect refused; credentials/text not forwarded |
| `http://127.0.0.1:8765/timeout/v1` | Cancel while waiting, or wait for timeout; source remains unchanged |

Also perform these manual checks:

1. **Cancellation:** use the timeout fixture, press Send, then Cancel. Start a new normal request. The cancelled result must never overwrite the newer result. During the brief replacement/readback phase, cancellation and conflicting actions are intentionally unavailable so the app can report the actual write outcome.
2. **Offline:** stop the mock with Ctrl-C and send a scratchpad sample. Confirm a connection error and intact source text. Restart the mock to continue.
3. **Invalid model/key:** use the normal `/v1` URL with model `wrong-alias`, then separately save test key `incorrect-test-key`. Expect model/authentication guidance. Restore `mock-editor` and `local-test` afterward.
4. **Allowlist:** disable the application being tested, save/close Settings, and try its shortcut capture. Capture must be denied. Re-enable it to continue. Manual paste remains an explicit user action.
5. **No automatic inference:** capture, change focus, and edit the preview without pressing WriteDock’s Send button. No suggestion should be generated. Settings explain the outgoing text and preferences; only that reviewed text is submitted. The surrounding field may be read locally for stale-text checks; only a bounded snapshot is retained, and it is not sent.
6. **Keychain persistence:** with the normal mock configuration saved, quit and relaunch WriteDock. Send a scratchpad sample without re-entering the key. It should succeed. The SecureField should remain blank; saved credentials must not appear in ordinary settings or logs.
7. **Endpoint isolation:** change the mock base URL from `http://127.0.0.1:8765/v1` to `http://localhost:8765/v1` without entering a new key. Expect a missing-key error, proving the previous URL’s credential is not silently reused. Restore the original URL and retry.
8. **Key removal:** remove the saved key for the active URL and send. Expect missing-key guidance. Save `local-test` again only if more mock testing is needed.
9. **Restart privacy:** quit and relaunch with text and a suggestion visible. Source text and suggestion must not be restored as writing history. Non-secret provider/preferences settings may persist.

For every manual run, record application version, WriteDock build, permission state, capture method, sample, result, formatting changes, caret position, and whether the automatic or manual fallback path was used. Do not mark any pending application row passed until these checks have been observed in that application.
