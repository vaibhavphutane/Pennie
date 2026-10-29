import AppKit
import SwiftUI
import PennieCore

enum MascotAsset {
    static let image: NSImage? = {
        // Packaged .app uses its own resource directory; swift run uses SwiftPM's bundle.
        let url = Bundle.main.url(forResource: "Pennie", withExtension: "png") ?? Bundle.module.url(forResource: "Pennie", withExtension: "png")
        return url.flatMap(NSImage.init(contentsOf:))
    }()
}

struct PennieMascot: View {
    var size: CGFloat = 64
    var animated = true
    var thinking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var float = false
    var body: some View {
        Group {
            if let image = MascotAsset.image { Image(nsImage: image).resizable().interpolation(.high).scaledToFit() }
            else { Image(systemName: "pencil.tip.crop.circle.fill").resizable().scaledToFit().foregroundStyle(.teal) }
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(animated && !reduceMotion && float ? (thinking ? 7 : 3) : -2))
        .offset(y: animated && !reduceMotion && float ? -3 : 0)
        .animation(animated && !reduceMotion ? .easeInOut(duration: thinking ? 0.7 : 2.4).repeatForever(autoreverses: true) : nil, value: float)
        .onAppear { float = true }
        .accessibilityHidden(true)
    }
}

private struct PennieButton: View {
    @ObservedObject var settings: AppSettings
    let open: () -> Void
    let pause: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: open) {
            ZStack(alignment: .bottomTrailing) {
                PennieMascot(size: 68, animated: settings.animateMascot)
                    .shadow(color: .black.opacity(hovered ? 0.25 : 0.16), radius: 4, y: 3)
                Image(systemName: "sparkle").font(.system(size: 10, weight: .bold)).foregroundStyle(Color(red: 0.03, green: 0.29, blue: 0.24))
                    .padding(5).background(Color(red: 0.73, green: 0.97, blue: 0.86), in: Circle()).offset(x: -3, y: -5)
            }.frame(width: 72, height: 80).contentShape(Rectangle())
        }
        .buttonStyle(.plain).scaleEffect(hovered ? 1.06 : 1)
        .animation(.easeOut(duration: 0.15), value: hovered)
        .onHover { hovered = $0 }
        .help("Pennie · Say it like you.")
        .accessibilityLabel("Pennie, your writing companion")
        .accessibilityHint("Review the current selection or draft. No text is sent until you request a writing action.")
        .contextMenu { Button("Pause Pennie in this app", action: pause) }
    }
}

struct WidgetCard: View {
    @ObservedObject var state: EditorState
    @ObservedObject var settings: AppSettings
    let demo: Bool
    let close: () -> Void
    let expand: () -> Void
    let configure: () -> Void
    let pause: () -> Void
    private let ink = Color(red: 0.08, green: 0.19, blue: 0.18)
    private let muted = Color(red: 0.36, green: 0.43, blue: 0.41)
    private let green = Color(red: 0.06, green: 0.40, blue: 0.31)
    var body: some View {
        GeometryReader { geometry in
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PennieMascot(size: 55, animated: settings.animateMascot, thinking: state.busy)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ProductIdentity.name).font(.system(size: 17, weight: .semibold, design: .rounded)).foregroundStyle(ink)
                    Text(ProductIdentity.tagline).font(.system(size: 12)).foregroundStyle(muted)
                    Text(demo ? "Local preview · no text sent" : state.origin).font(.system(size: 11, weight: .medium)).foregroundStyle(muted).lineLimit(1)
                }
                Spacer(minLength: 0)
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).frame(width: 26, height: 26) }
                    .buttonStyle(.plain).foregroundStyle(muted).background(ink.opacity(0.05), in: Circle())
                    .help("Close and clear preview").accessibilityLabel("Close writing preview").disabled(state.replacing)
            }
            HStack(spacing: 6) {
                ForEach([WritingAction.grammar, .clarity, .brevity], id: \.self) { action in actionButton(action) }
            }
            if demo {
                HStack { Text("Writing action"); Spacer(); Text(state.action.label); Image(systemName: "chevron.up.chevron.down") }.font(.system(size: 11)).foregroundStyle(ink)
            } else { WritingActionPicker(state: state).font(.system(size: 11)) }
            ActionDetails(state: state).font(.system(size: 11)).disabled(demo)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("YOUR WORDS").font(.system(size: 9, weight: .bold)).tracking(1.3)
                    Spacer()
                    Text("\(state.source.utf16.count)/12,000").font(.system(size: 10, design: .monospaced))
                }.foregroundStyle(muted)
                Group {
                    if demo {
                        Text(state.source).font(.system(size: 13)).foregroundStyle(ink).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    } else {
                        TextEditor(text: $state.source).font(.system(size: 13)).scrollContentBackground(.hidden).disabled(state.busy)
                    }
                }.padding(8).frame(height: state.suggestion.isEmpty ? 90 : 55)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(ink.opacity(0.1)))
            }
            if !state.suggestion.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Image(systemName: "sparkles")
                        Text(state.resultTitle).tracking(1)
                    }.font(.system(size: 9, weight: .bold)).foregroundStyle(green)
                    if demo {
                        Text(state.suggestion).font(.system(size: 13)).foregroundStyle(ink).frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                    } else {
                        ScrollView {
                            SuggestionText(state: state).font(.system(size: 13)).foregroundStyle(ink)
                        }.frame(maxHeight: 100)
                    }
                }.padding(12).background(Color(red: 0.88, green: 0.96, blue: 0.90), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    if state.canApplyResult {
                        if demo { Label("Show changes", systemImage: "square") }
                        else { Toggle("Show changes", isOn: $state.showChanges).toggleStyle(.checkbox) }
                    }
                    Spacer()
                    Button("Regenerate") { state.send(regenerate: true) }.disabled(!state.canSend || demo)
                }.font(.system(size: 11)).foregroundStyle(ink)
                HStack(spacing: 8) {
                    Button(state.accepted ? "Accepted ✓" : "Accept") { state.accept() }.disabled(!state.canApplyResult || state.accepted || state.busy || demo)
                    Button("Copy") { state.copy() }.disabled(state.busy || demo)
                    Spacer(minLength: 0)
                    Button("Dismiss") { state.resetResult(); state.status = "Suggestion dismissed." }.disabled(state.busy || demo)
                }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(green)
            }
            HStack {
                if state.busy {
                    ProgressView().controlSize(.small)
                    Text(state.replacing ? "Applying…" : "Working on your words…").font(.system(size: 12)).foregroundStyle(muted)
                    Spacer()
                    if !state.replacing { Button("Cancel") { state.cancel() }.buttonStyle(.plain) }
                } else {
                    Button { state.send() } label: {
                        HStack {
                            Text(state.action.callToAction)
                            Spacer()
                            Image(systemName: state.action.isAnalysis ? "text.magnifyingglass" : "pencil.line")
                        }.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 14).padding(.vertical, 11)
                            .foregroundStyle(.white).background(green, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(.plain).disabled(demo || !state.canSend)
                        .help("Send this passage and your writing instructions to the displayed model.")
                }
            }
            Text(state.status).font(.system(size: 11)).foregroundStyle(muted).lineLimit(4).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 3) {
                Text(settings.provider.model.isEmpty ? "Choose a model in Settings" : settings.provider.model).lineLimit(1)
                Text(settings.provider.baseURL.isEmpty ? "Add your inference endpoint" : settings.provider.baseURL).lineLimit(1).truncationMode(.middle)
                Text("“\(state.action.callToAction)” sends your words and writing instructions to this model.")
            }.font(.system(size: 9)).foregroundStyle(muted)
            HStack {
                Button("Settings", action: configure)
                Button("Pause here", action: pause)
                Spacer()
                Button { expand() } label: { Label("Open editor", systemImage: "arrow.up.left.and.arrow.down.right") }
            }.font(.system(size: 10, weight: .medium)).buttonStyle(.plain).foregroundStyle(green).disabled(state.replacing || demo)
        }
        .frame(maxWidth: .infinity, minHeight: max(0, geometry.size.height - 36))
        .padding(18)
        }
        }
        .background(Color(red: 0.98, green: 0.98, blue: 0.95))
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(ink.opacity(0.12)))
        .environment(\.colorScheme, .light)
    }
    private func actionButton(_ action: WritingAction) -> some View {
        let title: String
        switch action {
        case .grammar: title = "Fix grammar"
        case .clarity: title = "Clearer"
        case .brevity: title = "Shorter"
        case .professional: title = "Professional"
        case .conversational: title = "Conversational"
        default: title = action.label
        }
        return Button { state.action = action } label: {
            Text(title).font(.system(size: 11, weight: .medium)).padding(.horizontal, 10).padding(.vertical, 7)
                .foregroundStyle(state.action == action ? .white : ink)
                .background(state.action == action ? green : ink.opacity(0.05), in: Capsule())
        }.buttonStyle(.plain).disabled(state.busy || demo)
            .accessibilityAddTraits(state.action == action ? .isSelected : [])
    }
}

private final class CompanionPanel: NSPanel {
    var acceptsKeyboard = false
    var onEscape: (() -> Void)?
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onEscape?() }
}
private final class CompanionHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class FloatingWidgetController {
    private let state: EditorState
    private let settings: AppSettings
    private let bridge = AccessibilityBridge()
    private let openEditor: () -> Void
    private let openSettings: () -> Void
    private let bubble = CompanionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let card = CompanionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var timer: Timer?
    private var anchor: EditorAnchor?
    private var visibleAppID: String?
    private var visibleProcessID: pid_t?
    private let diagnosticsURL: URL?
    private var lastDiagnostics: Data?
    private var demo = false
    private let cardSize = CGSize(width: 368, height: 610)

    init(state: EditorState, settings: AppSettings, diagnosticsURL: URL? = nil, openEditor: @escaping () -> Void, openSettings: @escaping () -> Void) {
        self.state = state; self.settings = settings; self.openEditor = openEditor; self.openSettings = openSettings
        self.diagnosticsURL = diagnosticsURL
        for panel in [bubble, card] {
            panel.isFloatingPanel = true; panel.level = .floating; panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.isReleasedWhenClosed = false
            panel.hasShadow = panel === card; panel.animationBehavior = .none
        }
        bubble.title = "Pennie"; card.title = "Pennie writing preview"
        card.acceptsKeyboard = true
        card.onEscape = { [weak self] in self?.dismiss() }
        bubble.contentView = CompanionHostingView(rootView: PennieButton(settings: settings, open: { [weak self] in self?.openCard() }, pause: { [weak self] in self?.pauseHere() }))
        installCard(demo: false)
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.7, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        timer?.tolerance = 0.15
        refresh()
    }
    func stop() { timer?.invalidate(); timer = nil; dismiss(); bubble.orderOut(nil) }

    func refresh() {
        guard !demo, !state.replacing else { return }
        defer { writeDiagnostics() }
        let enabled = settings.allowedApps.subtracting(settings.pausedWidgetApps)
        guard settings.widgetEnabled else { settings.widgetStatus = "Pennie is paused. Enable the floating widget above."; hide(); return }
        guard let app = NSWorkspace.shared.frontmostApplication,
              let bundle = app.bundleIdentifier, enabled.contains(bundle) else {
            settings.widgetStatus = AccessibilityBridge.isTrusted ? "Switch to an allowed app to show Pennie. Check the app list and paused apps below." : "Enable Accessibility for this Pennie app to capture text."
            hide(); return
        }
        // A key nonactivating panel can temporarily move keyboard focus away from the host field.
        // Keep this captured preview stable while it is being edited; replacement revalidates later.
        if card.isVisible, card.isKeyWindow, visibleProcessID == app.processIdentifier,
           AccessibilityBridge.isTrusted || anchor == nil { return }
        guard let current = bridge.focusedEditor(allowedBundleIDs: enabled),
              let primary = NSScreen.screens.first else { showDocked(for: app); return }
        let rect = FloatingPlacement.cocoaRect(fromAX: current.bounds, primaryTop: primary.frame.maxY)
        guard let screen = FloatingPlacement.visibleScreen(for: rect, screens: NSScreen.screens.map(\.visibleFrame)),
              let frame = FloatingPlacement.widgetFrame(editor: rect, screen: screen) else { showDocked(for: app); return }
        if card.isVisible, visibleProcessID != app.processIdentifier || (anchor != nil && !anchor!.isSameField(as: current)) { dismiss() }
        // An open docked scratchpad stays put until dismissed; never discard typed text on detection.
        if card.isVisible, anchor == nil { return }
        anchor = current
        visibleAppID = bundle; visibleProcessID = app.processIdentifier
        settings.widgetStatus = "Pennie is beside the editor in \(app.localizedName ?? bundle)."
        bubble.setFrame(frame, display: true)
        if !bubble.isVisible { bubble.orderFrontRegardless() }
        if card.isVisible { card.setFrame(FloatingPlacement.cardFrame(widget: frame, screen: screen, size: cardSize), display: true) }
    }

    private func showDocked(for app: NSRunningApplication) {
        if card.isVisible, visibleProcessID != app.processIdentifier || anchor != nil { dismiss() }
        anchor = nil; visibleAppID = app.bundleIdentifier; visibleProcessID = app.processIdentifier
        settings.widgetStatus = AccessibilityBridge.isTrusted
            ? "Pennie is in the lower-right corner. Click the message compose box to attach it to an editor, or click Pennie for capture guidance."
            : "Pennie is in the lower-right corner. Enable Accessibility for Pennie to capture text."
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let screen, let frame = FloatingPlacement.dockedWidgetFrame(screen: screen.visibleFrame) else { hide(); return }
        // Keep a docked card stable while the user moves the pointer into it.
        if card.isVisible { return }
        bubble.setFrame(frame, display: true)
        if !bubble.isVisible { bubble.orderFrontRegardless() }
    }

    private func writeDiagnostics() {
        guard let diagnosticsURL else { return }
        // Explicit debug mode only: no text, window titles, keys, or provider URLs.
        let snapshot: [String: Any] = [
            "pid": ProcessInfo.processInfo.processIdentifier,
            "accessibilityTrustedForPennie": AccessibilityBridge.isTrusted,
            "frontmostBundleID": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown",
            "widgetEnabled": settings.widgetEnabled, "bubbleVisible": bubble.isVisible,
            "cardVisible": card.isVisible, "anchoredToEditor": anchor != nil,
            "widgetFrame": [bubble.frame.minX, bubble.frame.minY, bubble.frame.width, bubble.frame.height],
            "reason": settings.widgetStatus
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted, .sortedKeys]), data != lastDiagnostics else { return }
        do { try data.write(to: diagnosticsURL, options: .atomic); lastDiagnostics = data } catch { /* Diagnostics must never interrupt writing. */ }
    }

    func dismiss(clear: Bool = true) {
        card.orderOut(nil)
        if clear && !state.replacing {
            state.resetResult(); state.capture = nil; state.source = ""; state.origin = "Scratchpad"
        }
    }
    private func hide() {
        if card.isVisible { dismiss() }
        bubble.orderOut(nil); anchor = nil
        visibleAppID = nil; visibleProcessID = nil
    }
    private func openCard() {
        guard !state.busy, !demo else { return }
        if card.isVisible { dismiss(); return }
        // Revalidate before capture: clicking a stale floating button must not read another field.
        guard settings.widgetEnabled, let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier == visibleProcessID, let bundle = app.bundleIdentifier,
              settings.allowedApps.subtracting(settings.pausedWidgetApps).contains(bundle) else { hide(); return }
        if let anchor {
            guard let current = bridge.focusedEditor(allowedBundleIDs: settings.allowedApps.subtracting(settings.pausedWidgetApps)),
                  current.isSameField(as: anchor) else { refresh(); return }
            state.captureFromWidget(current)
        } else {
            // Explicit click only. Capture the draft even if its editor has no usable bounds.
            _ = state.captureText()
            if state.capture == nil { state.origin = app.localizedName ?? bundle }
        }
        guard let screen = FloatingPlacement.visibleScreen(for: bubble.frame, screens: NSScreen.screens.map(\.visibleFrame)) else { hide(); return }
        card.setFrame(FloatingPlacement.cardFrame(widget: bubble.frame, screen: screen, size: cardSize), display: true)
        // The nonactivating panel keeps the host app frontmost. It becomes key only for input inside the card.
        card.orderFrontRegardless()
    }
    private func pauseHere() {
        if let bundle = visibleAppID { settings.pausedWidgetApps.insert(bundle); settings.save() }
        hide()
    }
    private func installCard(demo: Bool) {
        card.contentView = CompanionHostingView(rootView: WidgetCard(state: state, settings: settings, demo: demo,
            close: { [weak self] in if demo { NSApp.terminate(nil) } else { self?.dismiss() } },
            expand: { [weak self] in self?.dismiss(clear: false); self?.openEditor() },
            configure: { [weak self] in self?.dismiss(clear: false); self?.openSettings() },
            pause: { [weak self] in self?.pauseHere() }))
    }
    var hasNonactivatingPanels: Bool {
        [bubble, card].allSatisfy { $0.styleMask.contains(.nonactivatingPanel) && !$0.canBecomeMain }
            && !bubble.canBecomeKey && card.canBecomeKey && timer == nil && !bubble.isVisible && !card.isVisible
    }
    var demoPanelsVisible: Bool { bubble.isVisible && card.isVisible && bubble.frame.width == 72 && card.frame.width > 0 }
    /// Explicit local fixture; no AX reads, inference, or source-app edits.
    func showDemo() {
        demo = true; timer?.invalidate(); timer = nil
        state.source = "This are a example. I has recieved teh message."
        state.suggestion = "This is an example. I have received the message."
        state.origin = "Demo draft"
        state.status = "Preview only. In a supported app, click Pennie to review your words."
        installCard(demo: true)
        let screen = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let widgetFrame = CGRect(x: screen.midX + 190, y: screen.midY - 260, width: 72, height: 80)
        bubble.setFrame(widgetFrame, display: true)
        card.setFrame(FloatingPlacement.cardFrame(widget: widgetFrame, screen: screen, size: cardSize), display: true)
        bubble.orderFrontRegardless(); card.orderFrontRegardless()
    }
}

@MainActor
final class WidgetDemoDelegate: NSObject, NSApplicationDelegate {
    private var controller: FloatingWidgetController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let settings = AppSettings(loadSaved: false)
        let state = EditorState(settings: settings)
        controller = FloatingWidgetController(state: state, settings: settings, openEditor: {}, openSettings: {})
        let menu = NSMenu(), root = NSMenuItem(), submenu = NSMenu()
        menu.addItem(root); root.submenu = submenu
        submenu.addItem(withTitle: "Quit Pennie Preview", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        NSApp.mainMenu = menu
        controller?.showDemo()
        if CommandLine.arguments.contains("--smoke-test-demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                precondition(self.controller?.demoPanelsVisible == true, "Demo windows did not open")
                print("PASS: native mascot and writing-card panels launched with synthetic text; no AX reads, key registration, settings writes, or inference.")
                NSApp.terminate(nil)
            }
        }
    }
}

@MainActor
enum WidgetStateChecks {
    private final class FixtureTextAccess: TextAccess {
        let snapshot = TextCapture(text: "This are a draft.", appName: "Fixture editor", bundleID: "com.tinyspeck.slackmacgap",
            bounds: nil, element: AXUIElementCreateApplication(987_001), processID: 987_001,
            range: CFRange(location: 0, length: 17), context: "This are a draft.",
            originalSelection: CFRange(location: 4, length: 0), isWholeDraft: true)
        var replacements = [String]()
        var failure: CaptureError?
        func capture(allowedBundleIDs: Set<String>, from anchor: EditorAnchor?) throws -> TextCapture { snapshot }
        func replace(capture: TextCapture, with replacement: String) async throws {
            replacements.append(replacement)
            await Task.yield()
            if let failure { throw failure }
        }
    }

    static func run() async {
        var count = 0
        func check(_ condition: Bool, _ name: String) { precondition(condition, name); count += 1 }
        let settings = AppSettings(loadSaved: false)
        let state = EditorState(settings: settings)
        state.source = "A sample draft."
        state.suggestion = "A polished draft."; state.accepted = true
        state.source = "An edited draft."
        check(state.suggestion.isEmpty && !state.accepted, "edited source invalidates preview approval")
        state.suggestion = "A suggestion."; state.action = .brevity
        check(state.suggestion.isEmpty, "action switch invalidates output")
        state.suggestion = "Original settings output."
        settings.backend = .liteLLM
        check(state.suggestion.isEmpty, "backend switch invalidates hidden and visible views equally")
        state.suggestion = "Old URL output."; settings.liteLLM.baseURL = "https://example.test/v1"
        check(state.suggestion.isEmpty, "endpoint change invalidates output")
        state.suggestion = "Old model output."; settings.liteLLM.model = "example"
        check(state.suggestion.isEmpty, "model change invalidates output")
        state.suggestion = "Old preferences output."; settings.preferences = "British English"
        check(state.suggestion.isEmpty, "writing preference changes invalidate output")
        state.suggestion = "Old OpenAI output."; settings.openAI.model = "fixture-openai"
        check(state.suggestion.isEmpty, "direct OpenAI settings invalidate pending output")
        state.suggestion = "Old Claude output."; settings.anthropic.baseURL = "https://example.test/v1"
        check(state.suggestion.isEmpty, "direct Claude settings invalidate pending output")
        state.busy = true
        let task = Task<Void, Never> {}; state.request = task
        state.source = "New text."
        check(task.isCancelled && !state.busy && state.request == nil, "editing cancels in-flight inference")
        state.suggestion = "Replacement underway."; state.busy = true; state.replacing = true
        state.status = "Applying…"; state.cancel()
        check(state.busy && state.suggestion == "Replacement underway." && state.status == "Applying…", "cannot claim cancellation during replacement readback")
        state.replacing = false; state.busy = false
        state.resetResult(); state.source = "This is correct."; state.action = .grammar
        state.receive("This is correct.")
        state.accept()
        check(state.hasResponse && !state.canApplyResult && !state.accepted, "unchanged output cannot be accepted or applied")
        state.action = .improve; state.receive("This is correct.")
        check(state.status.contains("echoed") && !state.canApplyResult, "echo on rewrite explicitly reported as incomplete action")
        state.action = .tone; state.receive("Tone: neutral. Reader impact: clear.")
        state.accept()
        check(state.outcome == .analysis && !state.canApplyResult && !state.accepted, "tone report never becomes replacement text")
        state.action = .custom
        check(!state.canSend, "custom request requires an instruction")
        state.customInstruction = "Make it warmer"; state.receive("A warmer version.")
        check(state.canSend && state.canApplyResult, "custom rewrite can be reviewed")
        state.customInstruction = "Make it shorter"
        check(state.suggestion.isEmpty, "custom instruction changes invalidate result")
        state.action = .translate; state.receive("Bonjour")
        state.targetLanguage = "French"
        check(state.suggestion.isEmpty, "translation language changes invalidate result")
        state.receive("Bonjour"); settings.writingProfile.dialect = .british
        check(state.suggestion.isEmpty, "writing goals changes invalidate result")
        check(MascotAsset.image != nil, "mascot is bundled")
        if let url = Bundle.main.url(forResource: "Pennie", withExtension: "png") ?? Bundle.module.url(forResource: "Pennie", withExtension: "png"),
           let bitmap = NSBitmapImageRep(data: (try? Data(contentsOf: url)) ?? Data()) {
            check(bitmap.hasAlpha && bitmap.pixelsWide >= 512, "mascot preserves high-resolution alpha")
        } else { preconditionFailure("Mascot PNG missing") }
        let controller = FloatingWidgetController(state: state, settings: settings, openEditor: {}, openSettings: {})
        check(controller.hasNonactivatingPanels, "panels start hidden and do not activate or monitor other apps")
        controller.dismiss()
        check(state.source.isEmpty && state.suggestion.isEmpty, "closing clears draft and suggestion")

        let fixture = FixtureTextAccess()
        let captured = EditorState(settings: settings, allowsInference: false, bridge: fixture)
        let anchor = EditorAnchor(appName: fixture.snapshot.appName, bundleID: fixture.snapshot.bundleID,
            processID: fixture.snapshot.processID, bounds: .zero, element: fixture.snapshot.element)
        captured.captureFromWidget(anchor)
        check(captured.source == fixture.snapshot.text && captured.capture?.isWholeDraft == true && fixture.replacements.isEmpty,
              "opening beside an editor loads its draft and retains the writeback target")
        let capturedController = FloatingWidgetController(state: captured, settings: settings, openEditor: {}, openSettings: {})
        capturedController.dismiss(clear: false)
        check(captured.capture != nil && captured.source == fixture.snapshot.text, "expanding into the full editor keeps the original target")
        captured.receive("This is a draft.")
        captured.accept(); captured.accept()
        check(captured.busy && captured.replacing && !captured.accepted, "Accept starts applying and blocks duplicate clicks")
        await captured.request?.value
        check(fixture.replacements == ["This is a draft."] && captured.accepted && captured.capture == nil && !captured.busy,
              "one Accept writes the suggestion once and acknowledges success after verification")
        captured.accept()
        check(fixture.replacements.count == 1, "an accepted result cannot be written twice")

        _ = captured.captureText()
        check(captured.source == fixture.snapshot.text && captured.capture != nil, "shortcut capture also keeps the whole-draft target")
        captured.receive("This is a draft."); fixture.failure = .stale
        captured.accept(); await captured.request?.value
        check(!captured.accepted && captured.capture == nil && !captured.busy && captured.suggestion == "This is a draft." &&
              captured.status == CaptureError.stale.localizedDescription, "failed Accept retains copyable output and never claims success")

        _ = captured.captureText()
        captured.source = "An edited preview."
        captured.receive("A polished preview."); captured.accept()
        check(captured.capture == nil && captured.accepted && fixture.replacements.count == 2,
              "edited or pasted previews cannot overwrite a captured draft")
        _ = captured.captureText()
        captured.receive("This is a draft.")
        settings.allowedApps.remove(fixture.snapshot.bundleID)
        captured.accept()
        check(!captured.accepted && captured.capture == nil && fixture.replacements.count == 2,
              "disabling the source app prevents Accept from writing")
        print("PASS: \(count) widget state and resource checks; no AX reads, network requests, or saved-setting changes.")
    }
}

@MainActor
enum WidgetPreview {
    static func render(to url: URL) throws {
        let settings = AppSettings(loadSaved: false)
        settings.animateMascot = false
        settings.openRouter.model = "your-model"
        let state = EditorState(settings: settings)
        state.source = "This are a example. I has recieved teh message."
        state.suggestion = "This is an example. I have received the message."
        state.origin = "Slack · demo draft"
        state.status = "Review the suggestion, then accept or copy it. Your draft stays yours."
        let card = WidgetCard(state: state, settings: settings, demo: true, close: {}, expand: {}, configure: {}, pause: {})
        let preview = HStack(alignment: .bottom, spacing: 20) {
            card.frame(width: 368, height: 610)
            PennieMascot(size: 80, animated: false).padding(.bottom, 20)
        }.padding(32).background(Color(red: 0.90, green: 0.93, blue: 0.92))
        let renderer = ImageRenderer(content: preview)
        renderer.scale = 2
        guard let cg = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let bitmap = NSBitmapImageRep(cgImage: cg)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
}
