# Evidence and implementation decisions

Investigation date: 2026-10-28. Host: macOS 26.7.1, arm64. Scope: the user's downloaded Grammarly installer and installed Grammarly-family desktop client. This report separates shipped evidence, decompiler output, implementation choices, and runtime unknowns.

Raw evidence files referenced below are retained in the original local workspace and excluded from Git. The published report preserves findings, source identities, and evidence IDs; see [evidence availability](evidence/README.md).

## REA setup and target identity

Read the [REA repository documentation](https://github.com/morluto/rea) and locally installed reverse-engineering skill. REA 6.7.0 was already cached. Its doctor found an installed Hopper engine and missing Codex MCP registration; Ghidra/IDA were not configured. An initial `npx` fetch failed DNS; the existing pinned public launcher was used. Sandbox restrictions blocked REA's compiler cache and disk-image operations; approved execution outside the sandbox resolved the initial analysis blockers.

Instead of modifying global Codex settings or interrupting this task for a restart, `scripts/rea_mcp.py` launched the public `rea --mcp` stdio server, performed MCP initialization and `tools/list`, and used actual `tools/call` requests. **207 tools** were discovered. This is an MCP session, not shell output relabeled as REA. Global Codex MCP registration remains unchanged. Full schemas, initialization, doctor results, exact request batches, and response envelopes are retained in `docs/evidence/rea-*.json`.

The downloaded `Grammarly.o1.clRXLyd2dpfnaqhkirqr0002.dmg` is 127,226,309 bytes, SHA-256 `453d233e89c38e3c6b345d5a97ced2fa31ed5db992331e932942cf88d38eb4f1`. REA verified and mounted it read-only, producing an artifact graph with 843 nodes and 1,129 occurrences. Its `Grammarly Installer.app` declares **1.199.0 / 1.199.0.0**, bundle `com.grammarly.ProjectLlama`, executable `Grammarly Desktop`. The later read-only mount was detached after inspection; the installer was never executed.

The installed `/Applications/Superhuman Go.app` declares **1.200.0 / 1.200.0.0**, the same bundle ID, and executable `Grammarly Superhuman Go`. These artifacts differ and are not interchangeable. Installed binaries inspected are universal Mach-O (arm64 + x86_64), with native Swift/Objective-C, AppKit/ApplicationServices, multiple native frameworks, XPC services, helper apps, and packaged JavaScript. The inventory does not establish that the desktop app is Electron.

## Principal REA evidence

Full IDs below can be searched in the saved JSON. Native virtual addresses refer to the installed framework's arm64 analysis image; shell string offsets in the separate static ledger refer to file bytes.

| Evidence | What it establishes | Limit |
|---|---|---|
| `ev_f0f30ee2dfc8d0c1e24b030c4515878f40d1310b9e06f45b5c7e946d2993538d` | Downloaded DMG inspected; embedded inventory `ev_10a23d62ad452ce547c0973b44e966735bf02b7b33ca0d6d34975d00b10c66c8` and graph `agm_8a4a6d2f27c6899e21fec6714cbf2e49778568a2e297836163f31231bdec1f52` | Inventory does not execute components |
| `rea-download-requests-1-inspect_plist.json` | REA parsed installer Info.plist, confirming 1.199.0 | Downloaded client, not installed version |
| `ev_fbfcfdefacd1a481507c98be5dcf65fa42cae3f4090229af884de18ab002f536` | Installed GRAccessibilityKit Mach-O summary: 2 architectures, arm64 selected, 34 dependencies | Symbol collections are not exhaustive; complete parent was retained during that session |
| `ev_875bff08670c74ec0aa6a958d50498b6b1a4b039feeb672a7cffed0e56cb0fb9` | Hopper resolves selectedText, setSelectedText, selectedTextRange, setSelectedTextRange, selectedTextMarkerRange, and getSelectedTextWithBrowserFallback symbols | Static procedure discovery, not observed app execution |
| `ev_e964dd893c8f1f7e9164f94dc1d14910eb81d7f597207e2aa3d002b0c535d1f8` | `AXBoundsForRange` literal at `0x47500` | String presence alone cannot establish use |
| `ev_9d8ab6bc0c8cdd20e1138e18c7619c1766e17abf5feb280ca22237b7c2995cda` | Decompiled `0x107c8` dispatches with selectedText attribute key | Recovered pseudocode is not original source |
| `ev_8301ad781b552cbb983768d70f0bec8f2be41de7f91f0184377ec71d89aa04e3` | Decompiled setter `0x107fc` dispatches with selectedText key | Helper body/call-chain not fully reconstructed |
| `ev_df09d9de5db5270153bdcc1a71aef62cadc487e80bc2bb5e1ea9878451efbf81` | Decompiled `0x10ec4` uses selectedTextRange key | Does not prove cursor restoration order |
| `ev_629630d5531a02199cc3bfb56f54224ec8fbab958c54f7d4706ffa348cfb3c3a` | Browser-fallback helper `0x2d0bc` references selectedText and stringForTextMarkerRange | Decompiler has unresolved/register artifacts, including impossible-looking conditions; exact branch semantics remain uncertain |

The installed native-function session is exported in `evidence/rea-native-bundle.json`. Downloaded-framework follow-up failed in Hopper with `Cannot launch Hopper! Connection is invalid.` REA reported `cleanup_incomplete`, retaining `/tmp/rea-Cp5WzP`; closure of that private Hopper resource was not confirmed. No successful downloaded-version pseudocode is claimed. The read-only mounted volume was detached. The failed responses are preserved rather than hidden. A future pass should complete/close the reported Hopper document before reopening this target.

## Behavior-to-design map

The [static ledger](static-findings.md) provides hashes, exact offsets, commands, and app-specific resource line references for the following complementary shell observations.

| Requested behavior | Evidence-backed finding | Independent WriteDock decision |
|---|---|---|
| Editable text detection | AX focus/observer imports and Outlook/Slack/Teams configuration rules are packaged | Use public AX focused-element capture with explicit app allowlist, editable-role checks, secure-field rejection; no typing monitor |
| Reading / selection / positioning | AX selection, range, text-marker and bounds symbols; selectedText wrappers recovered by REA | Capture a single UTF-16 selection on shortcut; show near-selection preview when bounds exist; ordinary window otherwise |
| Grammar / rewrites / preview | Native preview/view-model names and formal/shorten/friendly command symbols | Side-by-side plain-text preview; five independently authored prompts; Accept, Dismiss, Replace, Copy |
| Formatting / focus / cursor | Dedicated HTML/attributed-string/pasteboard replacement strategy names | Use only writable AXSelectedText with unchanged context/range/focus checks and readback; set and verify caret; never overwrite AXValue; manual copy/paste when verification cannot be supported |
| Shortcuts / background / IPC | Shortcut recorder types; helper/login/updater/web-content components; NSXPCConnection and JS bridge imports | One local process, menu bar item, Carbon ⌘⇧G shortcut; no background service, injection, XPC recreation, or synthetic keystroke replay |
| Local / cloud | Native network/WebSocket and text-action-session components are present | Local capture/UI/Keychain; explicit HTTP inference through selected OpenRouter or LiteLLM endpoint; no requests to Grammarly |

The formatting strategy names demonstrate that formatting requires dedicated logic. They do not supply a recovered algorithm. WriteDock's simpler path intentionally limits automatic editing to cases it can verify. Even a verified text replacement does not prove that every bold/link/list style run was preserved. There are no continuous red underlines or per-word overlays in this version. The practical fallback is selected-text copy/paste.

## Runtime and recovery limits

The application build launches. Local HTTP inference and pure replacement guards can be tested without inspecting private work. Metadata-only diagnostics found Outlook 16.113.4, Teams 26261.303.5165.1465, and Slack 4.52.171 running, but Accessibility trust was false. No successful live capture/replacement/formatting/cursor checks in those applications are claimed. See [VALIDATION.md](VALIDATION.md) for the recorded matrix and sample-only steps.

A bounded REA `observe_native_ui` request targeted WriteDock's own process/window, with screenshots disabled. After binding the built app as required, it returned `accessibility-denied: Grant Accessibility to the REA host`, retained in `evidence/rea-rea-runtime-requests-1-observe_native_ui.json`. The initial unbound request is also retained. The metadata helper reported screen-capture permission false. Grammarly was not among the running matched applications. No private draft text or screenshots of Outlook, Teams, or Slack were collected. The request files contain session-specific process/window IDs; refresh the metadata inventory before repeating runtime observations.

No Grammarly cloud traffic was captured, and no model weights, server prompts, training data, ranking system, backend entitlement logic, or online experimentation rules were recovered. The artifacts support network-capable session components; they do not prove that all grammar processing is remote or that no local linguistic functionality exists. Grammarly's runtime selection reconciliation, rich-format patching, shortcut defaults, request schemas, and effective per-app fallback ordering remain unresolved.

The new application uses its own code, prompts, layout, and public macOS APIs. Evidence excerpts are retained only for analysis; no proprietary binaries, fonts, icons, or JavaScript are linked or shipped in WriteDock.
