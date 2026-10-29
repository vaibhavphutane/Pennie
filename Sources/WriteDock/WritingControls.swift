import AppKit
import SwiftUI
import WriteDockCore

/// Shared action catalog: the editor and Nib expose exactly the same operations.
struct WritingActionPicker: View {
    @ObservedObject var state: EditorState
    var body: some View {
        Picker("Writing action", selection: $state.action) {
            ForEach(WritingAction.groups, id: \.self) { group in
                Section(group) {
                    ForEach(WritingAction.allCases.filter { $0.group == group }) { Text($0.label).tag($0) }
                }
            }
        }.pickerStyle(.menu).disabled(state.busy).accessibilityLabel("Writing action")
    }
}

struct ActionDetails: View {
    @ObservedObject var state: EditorState
    var body: some View {
        if state.action == .custom {
            TextField("For example: make this warmer and keep it under 50 words", text: $state.customInstruction, axis: .vertical)
                .lineLimit(2...3).textFieldStyle(.roundedBorder).disabled(state.busy).accessibilityLabel("Custom editing request")
            Text("\(state.customInstruction.count)/1,000 · Sent with your text").font(.caption2).foregroundStyle(.secondary)
        } else if state.action == .translate {
            TextField("Target language", text: $state.targetLanguage).textFieldStyle(.roundedBorder)
                .disabled(state.busy).accessibilityLabel("Target language")
        }
    }
}

struct SuggestionText: View {
    @ObservedObject var state: EditorState
    private var display: AttributedString {
        guard state.showChanges, state.canApplyResult else { return AttributedString(state.suggestion) }
        var text = AttributedString()
        for span in SuggestionDiff(source: state.source, result: state.suggestion).spans {
            var value = AttributedString(span.text)
            switch span.kind {
            case .added: value.foregroundColor = .green; value.backgroundColor = .green.opacity(0.12)
            case .removed: value.foregroundColor = .red; value.strikethroughStyle = .single
            case .unchanged: break
            }
            text += value
        }
        return text
    }
    var body: some View { Text(display).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading) }
}

@MainActor
final class WritingPreviewDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings(loadSaved: false)
        settings.openRouter.model = "Preview only"
        let state = EditorState(settings: settings, allowsInference: false)
        state.source = "This are a example. I has recieved teh message."
        state.receive("This is an example. I have received the message.")
        state.showChanges = true
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--preview-action"), args.indices.contains(index + 1), let action = WritingAction(rawValue: args[index + 1]) {
            state.action = action
            if action == .custom { state.customInstruction = "Make this warm and concise." }
            if action == .translate { state.targetLanguage = "French" }
        }
        if args.contains("--preview-result") {
            state.receive("This is an example. I have received the message. Thank you for sharing it.")
            state.showChanges = true
        }
        state.status = "Local UI preview. Inference and app capture are disabled."
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 740), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window?.title = "WriteDock Writing Preview"
        if args.contains("--preview-nib") {
            window?.setContentSize(NSSize(width: 368, height: 610))
            window?.contentView = NSHostingView(rootView: WidgetCard(state: state, settings: settings, demo: false, close: {}, expand: {}, configure: {}, pause: {}))
        } else {
            window?.contentView = NSHostingView(rootView: EditorView(state: state, settings: settings, showSettings: {}))
        }
        window?.center(); window?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if args.contains("--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if let view = self.window?.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let suffix = args.contains("--preview-nib") ? "nib" : "editor"
                    let url = URL(fileURLWithPath: "docs/evidence/writing-\(suffix)-preview.png")
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
                }
                NSApp.terminate(nil)
            }
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
