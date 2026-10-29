# Testing WriteDock

Run these commands from the repository root on macOS with Apple's Command Line Tools and Python 3 installed:

```bash
bash scripts/build-app.sh
bash scripts/test-core.sh
bash scripts/test-loopback.sh
bash scripts/test-accessibility.sh
bash scripts/test-widget.sh
dist/WriteDock.app/Contents/MacOS/WriteDock --check-widget-state
dist/WriteDock.app/Contents/MacOS/WriteDock --check-settings-migration
```

Full Xcode installations can additionally run `swift test`. The standalone Command Line Tools may not include XCTest; the scripts above provide a dependency-free harness. Generated test output stays local and is ignored by Git.

## Automated coverage

| Check | Coverage |
| --- | --- |
| Core | Four backend request formats, all 16 writing actions, goals and dictionary guidance, custom instructions, translation language, regeneration, input limits, error handling, cancellation, and redirect refusal |
| Result review | Unchanged output and tone-report classification; exact reconstruction of source and result from Unicode-aware diff spans; bounded work for long passages |
| Loopback HTTP | Actual URLSession requests to a temporary local server, five deterministic writing fixtures, provider-specific authentication and model routing, and unsuccessful responses |
| Replacement guards | UTF-16 ranges, grapheme boundaries, surrounding text, stale selections, invalid and overflowing ranges |
| Widget placement | Multiple displays, edge placement, clipping, offscreen and invalid frames, and corner fallback |
| Widget state | Source/action/settings changes invalidate results, cancellation, nonactivating panels, resource loading, and preventing unchanged text or analysis reports from being applied |
| Settings migration | Older provider settings remain readable; provider configurations remain independent |

The loopback script starts a server on an OS-assigned port and stops only its own child process. Its deterministic responses validate transport behavior, not model quality.

For a separate macOS Keychain integration check:

```bash
dist/WriteDock.app/Contents/MacOS/WriteDock --check-keychain
```

This creates temporary synthetic credentials, checks session caching and provider/URL isolation, and removes its fixture. It does not read configured provider credentials. macOS may require authorization for Keychain changes.

## Check a configured backend

In Settings, save the API base URL, model, and key, then choose **Test correction with sample text**. The displayed sample is the only writing text sent. This uses the selected backend's inference quota.

To test all 16 actions using synthetic passages:

```bash
dist/WriteDock.app/Contents/MacOS/WriteDock --check-configured-backend
```

This command uses the selected backend and saved key. It sends no captured application text or personal writing preferences. It prints synthetic outputs, never the key. A distinct output is not proof of a good edit: review meaning, factual accuracy, tone, and formatting. Live provider checks are separate from local fixture tests.

## Manual application checks

Enable the current WriteDock bundle in **System Settings → Privacy & Security → Accessibility**. Check its permission status in WriteDock Settings. The helper process's permission is separate from the app's permission; rebuilding an ad-hoc-signed app can require renewing its grant.

Use synthetic text in unsent drafts:

| Application | Test surface |
| --- | --- |
| Outlook | New message body, with recipients left blank |
| Teams | Unsent draft in a chat with yourself |
| Slack | Unsent draft in your own conversation |

1. Type `This are a example. I has recieved teh message.` and select the passage.
2. Confirm Nib appears near the editor or in the display's lower-right corner. Click Nib, or press **⌘⇧G**, and check that the preview matches the selection.
3. Choose **Grammar & spelling**, then **Send**. Review the result and **Show changes**.
4. Choose **Accept**, then **Replace selection**. Verify the corrected text, unchanged surrounding text, focus, and caret placement. Do not send the draft.
5. Repeat with **Rephrase**, a custom editing request, and translation. A tone-insights report must not enable Accept or Replace.
6. Check Copy and Dismiss. Correct source text may produce an unchanged result; it must not be offered as an applicable correction.
7. Capture again, then change the source selection or document before attempting replacement. Confirm stale replacement is refused.
8. Edit or redact the preview. Confirm direct replacement becomes unavailable and Copy remains usable after inference.
9. Click Nib with no selection. A readable draft can be previewed, but replacement must stay unavailable.

Repeat with emoji, combining characters, line breaks, lists, bold text, and links. Text replacement alone does not guarantee preservation of rich formatting. When the editor does not expose a writable selection, use manual copy/paste and review the result.

## Widget and failure checks

- Move, resize, scroll, and minimize the source window; test a second display. Nib should remain within visible bounds and use its corner fallback when editor geometry is unavailable.
- Switch apps or fields and close the preview. Check that obsolete captured text is cleared, while editing inside Nib keeps the card open.
- Pause Nib in one app, resume it in Settings, disable the widget globally, and test Reduce Motion.
- Verify protected fields cannot be captured. Disallowed applications should not show Nib.
- Switch the backend, model, URL, goals, or preferences during a request. Obsolete results must not be applied.
- Exercise authentication failures, rate limits, unavailable models, timeout, malformed output, and cancellation. Original application text must remain unchanged.
- Review a custom request with a long result in Nib. Scroll as needed to reach the preview controls and footer.

These manual checks are required for each application/version combination you intend to support. Passing unit and transport tests does not establish cross-application editing behavior.
