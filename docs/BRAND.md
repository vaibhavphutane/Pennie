# Pennie

**Say it like you.**

Pennie is the app and the companion. Use one name in the Dock, menu bar, windows, settings, help, and documentation.

## The story

Pennie is your familiar desk companion—the favorite pen you reach for when you want the words to come out right. Bring your thoughts. Pennie helps you shape them into writing that still sounds like you.

The product description is: **Your writing companion, powered by the model you choose.**

The author brings the meaning, chooses the model, and decides what to keep. Pennie provides grammar help, clearer wording, and another perspective on tone. Provider access and usage charges still apply; Pennie adds no writing subscription.

## The character

Use the existing mint companion with its fountain-pen crest and warm expression. Its name is Pennie everywhere. The same artwork belongs in the app icon, editor, settings, and floating companion; the menu bar uses a simple pen-tip symbol for readability at small sizes.

Keep the palette grounded in mint, deep ink green, and warm paper. Motion should be gentle, optional, and respect Reduce Motion. The character waits beside the editor and responds when invited. It does not scold, grade, or pressure the writer.

## The voice

Write like a thoughtful colleague: warm, brief, practical, and clear about what happens next.

| Moment | Language |
| --- | --- |
| Introduction | Say it like you. |
| Ready | Ready when you are. |
| Empty result | A fresh look at your words. |
| Working | Working on your words… |
| Review | Review the suggestion, then accept or copy it. |

Use plain labels for controls: **Your words**, **Writing action**, **Suggestion**, **Show changes**, **Accept**, and **Copy**. Accept updates the original text box in one step. Keep error messages specific and useful.

## Writing actions

The primary button describes the selected task: **Fix grammar**, **Make concise**, **Translate text**, or **Analyze tone**. Both interfaces use `WritingAction.callToAction`. Keep the provider, endpoint, and model visible beside the workflow, with a clear explanation that pressing the task button sends the passage and writing instructions there.

Selecting an action does not send a request. Accepting a suggestion does not apply it. Replacement remains a separate, explicit step.

## Shared identity and compatibility

`ProductIdentity` in `Sources/PennieCore/ProductIdentity.swift` contains the name, tagline, descriptor, and story used by the app. Keep the README and packaged app metadata aligned with it.

The original bundle identifier (`local.WriteDock`) and Keychain service (`local.WriteDock.backend`) are compatibility identifiers, retained so existing settings and credentials remain accessible. They are not alternate product names. Legacy build environment variables and preview flags remain aliases for existing scripts.
