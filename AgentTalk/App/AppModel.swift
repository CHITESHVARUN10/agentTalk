import SwiftUI
import Observation
import AppKit
import ServiceManagement

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var phase: AppPhase = .Idle
    var modelPhase: ModelPhase = .NotInstalled
    var transcript: String = ""
    var partialTranscript: String = ""
    var errorMessage: String = ""
    var downloadProgress: Float = 0.0
    var downloadSpeed: String = ""
    var downloadRemaining: String = ""
    var audioLevel: Float = 0.0
    var copied = false
    var livePreviewEnabled: Bool = false

    private var panel: NSPanel?
    private var panelHost: NSHostingView<HUDContentView>?
    private var recordingStartedAt: Date?
    private var lastVisibleFrame: NSRect?
    private var pendingStartOnReady = false

    // ── Pill position (persisted) ─────────────────────────────
    /// Sticky anchor for the recording pill — set once per app run.
    private var recordingAnchor: NSPoint?
    /// Custom position mode (menu bar toggle, UserDefaults-backed).
    var usesCustomPosition: Bool = UserDefaults.standard.bool(forKey: "pillUsesCustomPosition")
    /// True while the user is dragging the dummy pill to pick a spot.
    var isPlacingPosition = false
    /// The dummy placement panel.
    private var placementPanel: NSPanel?
    /// Saved custom pill origin (screen coords).
    var customPillPosition: NSPoint? {
        get {
            let x = UserDefaults.standard.double(forKey: "pillCustomX")
            let y = UserDefaults.standard.double(forKey: "pillCustomY")
            guard x != 0 || y != 0 else { return nil }
            return NSPoint(x: x, y: y)
        }
        set {
            if let p = newValue {
                UserDefaults.standard.set(p.x, forKey: "pillCustomX")
                UserDefaults.standard.set(p.y, forKey: "pillCustomY")
            } else {
                UserDefaults.standard.removeObject(forKey: "pillCustomX")
                UserDefaults.standard.removeObject(forKey: "pillCustomY")
            }
        }
    }

    private init() {}

    func launch() {
        let ok = initialize_core()
        print("[AgentTalk] Core initialized: \(ok)")
        phase = get_app_phase()
        modelPhase = get_model_phase()
        livePreviewEnabled = get_live_preview_enabled()
        print("[AgentTalk] Initial phase: \(phase), model: \(modelPhase)")

        Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.audioLevel = get_audio_level()
        }

        // Max recording duration watchdog — auto-stops at 300s cap (5 min)
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.phase == .Recording else { return }
            let elapsed = self.recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            if elapsed > 300 {
                print("[AgentTalk] Recording timeout — auto stop")
                self.stopDictation()
            }
        }
    }

    // ── SINGLE dictation entry point ─────────────────────────
    //
    // Carbon hotkey (down/up) and menu bar both call this.
    // Behavior is driven entirely by the current phase.
    // Reentrancy-safe: hotkey-down + menu-click races collapse to one transition.

    func toggleDictation() {
        print("[State] toggleDictation — phase: \(phase), model: \(modelPhase)")

        switch phase {
        case .Ready:
            startDictation()
        case .Recording:
            stopDictation()
        case .TranscriptReady:
            // One press: close the transcript AND immediately start a new
            // recording. Same as clicking Close then pressing the hotkey.
            print("[State] TranscriptReady — close + start new recording")
            dismissTranscript()
            startDictation()
        case .Idle, .Preparing:
            // Model still loading/downloading. Queue a start for when Ready
            // arrives so the press is not lost, and show preparation feedback.
            print("[State] Model not ready — queuing start on Ready")
            pendingStartOnReady = true
            showPanel()
        default:
            // Processing, Error
            print("[State] toggleDictation ignored in phase \(phase)")
        }
    }

    private func startDictation() {
        print("[State] → Preparing/Recording start")
        let ok = start_recording()
        print("[State] start_recording returned: \(ok)")
        if ok {
            recordingStartedAt = Date()
            copied = false
            partialTranscript = ""
            showPanel()
        }
    }

    func toggleLivePreview() {
        livePreviewEnabled.toggle()
        set_live_preview_enabled(livePreviewEnabled)
        print("[AgentTalk] Live preview: \(livePreviewEnabled)")
    }

    // ── Launch at Login ──────────────────────────────────────

    /// Whether the app is registered to launch at user login.
    var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                print("[AgentTalk] Registered to launch at login")
            } else {
                try SMAppService.mainApp.unregister()
                print("[AgentTalk] Removed login item")
            }
        } catch {
            print("[AgentTalk] SMAppService error: \(error.localizedDescription)")
        }
    }

    // ── Pill position controls (menu bar) ────────────────────

    /// Show the draggable dummy pill so the user can pick a custom spot.
    func startPositionPlacement() {
        isPlacingPosition = true
        if placementPanel == nil {
            createPlacementPanel()
        }
        placementPanel?.orderFrontRegardless()
        print("[AgentTalk] Placement pill shown — drag and confirm")
    }

    /// User pressed ✓ on the dummy pill — save the spot.
    func confirmPositionPlacement() {
        guard let placementPanel else { return }
        customPillPosition = placementPanel.frame.origin
        usesCustomPosition = true
        UserDefaults.standard.set(true, forKey: "pillUsesCustomPosition")
        recordingAnchor = nil // real pill will use the saved spot next show
        dismissPlacementPanel()
        print("[AgentTalk] Custom position saved: \(placementPanel.frame.origin)")
    }

    /// Dismiss the dummy pill without saving.
    func cancelPositionPlacement() {
        dismissPlacementPanel()
        print("[AgentTalk] Placement cancelled")
    }

    private func dismissPlacementPanel() {
        placementPanel?.orderOut(nil)
        placementPanel = nil
        isPlacingPosition = false
    }

    private func createPlacementPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar + 1
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = false
        p.becomesKeyOnlyIfNeeded = true
        // Dummy pill is ALWAYS draggable — no recording needed.
        p.isMovable = true
        p.isMovableByWindowBackground = true

        p.contentView?.wantsLayer = true
        p.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        let host = NSHostingView(rootView: PlacementPillView(onConfirm: {
            Task { @MainActor in
                AppModel.shared.confirmPositionPlacement()
            }
        }))
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layer?.masksToBounds = false
        p.contentView = host

        // Start where the last custom position was, else bottom-center.
        if let saved = customPillPosition {
            p.setFrameOrigin(saved)
        } else if let screen = NSScreen.main {
            p.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - 120,
                y: screen.visibleFrame.minY + 24
            ))
        }

        placementPanel = p
    }

    /// Switch back to default (bottom-center) position.
    func setDefaultPosition() {
        usesCustomPosition = false
        UserDefaults.standard.set(false, forKey: "pillUsesCustomPosition")
        customPillPosition = nil
        recordingAnchor = nil
        dismissPlacementPanel()
        print("[AgentTalk] Default pill position restored")
    }

    /// Reset saved custom position (back to bottom-center).
    func resetCustomPosition() {
        customPillPosition = nil
        recordingAnchor = nil
        print("[AgentTalk] Custom pill position reset")
    }

    /// Called when the model finishes loading and phase becomes Ready.
    /// Starts a queued dictation if the user pressed the shortcut early.
    func flushPendingStart() {
        guard pendingStartOnReady, phase == .Ready else { return }
        pendingStartOnReady = false
        print("[State] Flushing queued start (model now Ready)")
        startDictation()
    }

    private func stopDictation() {
        print("[State] Recording Stopped — starting inference")
        recordingStartedAt = nil
        // FFI runs on main thread: captures audio (thread_local),
        // transitions to Processing, then spawns its own inference thread.
        stop_recording()
    }

    // ── Transcript actions ──────────────────────────────────

    func copyTranscript() {
        // Direct NSPasteboard write — one atomic clipboard event.
        // clearContents() then setString(_:forType:) bumps changeCount once,
        // so clipboard managers record the transcript as a single new entry.
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(transcript, forType: .string)
        let changeCount = pb.changeCount
        print("[AgentTalk] Copied to clipboard (changeCount: \(changeCount))")

        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.dismissTranscript()
        }
    }

    func closeTranscript() {
        dismissTranscript()
    }

    func dismissTranscript() {
        dismiss_transcript()
        hidePanel()
        resetHotkeyHeldState()
    }

    func retryRecording() { retry_recording() }

    // ── Panel management ────────────────────────────────────

    private func showPanel() {
        if panel == nil {
            createPanel()
        }
        resizePanelForCurrentState()
        positionPanelForCurrentState()
        panel?.orderFrontRegardless()
        print("[AgentTalk] Panel shown (state: \(phase))")
    }

    private func createPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 44),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar + 1
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isReleasedWhenClosed = false
        p.hidesOnDeactivate = false
        p.ignoresMouseEvents = false
        p.becomesKeyOnlyIfNeeded = true
        // The real pill is NOT draggable — position comes from the
        // placement dummy (custom mode) or the default anchor.
        p.isMovable = false
        p.isMovableByWindowBackground = false

        p.contentView?.wantsLayer = true
        p.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        let host = NSHostingView(rootView: HUDContentView())
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layer?.masksToBounds = false
        p.contentView = host

        panelHost = host
        panel = p
    }

    private func panelSizeForCurrentState() -> CGSize {
        switch phase {
        case .Recording:
            // Wider + taller when the live-preview bubble is visible above the pill
            let previewVisible = livePreviewEnabled && !partialTranscript.isEmpty
            if previewVisible {
                return CGSize(width: 400, height: 120)
            }
            return CGSize(width: 240, height: 44)
        case .Processing:
            return CGSize(width: 240, height: 44)
        case .TranscriptReady:
            return CGSize(width: 300, height: 170)
        case .Error, .Preparing:
            return CGSize(width: 300, height: 120)
        default:
            return CGSize(width: 240, height: 44)
        }
    }

    private func resizePanelForCurrentState() {
        guard let panel else { return }
        let size = panelSizeForCurrentState()
        let frame = NSRect(origin: panel.frame.origin, size: size)
        panel.setFrame(frame, display: true, animate: false)
        panelHost?.frame = NSRect(origin: .zero, size: size)
    }

    private func positionPanelForCurrentState() {
        guard let panel, let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame

        // Custom mode: honor the user's saved spot (set once per panel life),
        // never re-center on transitions — their placement wins.
        // Clamp into the visible frame so a stale/off-screen saved spot
        // (e.g. from a smaller screen) never loses the pill.
        if usesCustomPosition, let saved = customPillPosition, recordingAnchor == nil {
            var origin = saved
            origin.x = min(max(origin.x, visible.minX), visible.maxX - panel.frame.width)
            origin.y = min(max(origin.y, visible.minY), visible.maxY - panel.frame.height)
            panel.setFrameOrigin(origin)
            recordingAnchor = origin
            return
        }

        // Anchor: computed once (bottom-center), sticky for the whole run.
        if recordingAnchor == nil {
            recordingAnchor = NSPoint(
                x: visible.midX - panel.frame.width / 2,
                y: visible.minY + 24
            )
        }

        switch phase {
        case .TranscriptReady:
            // Float above the anchor, horizontally aligned to it — but never
            // off-screen: if the pill is near the top, put the transcript
            // BELOW the pill instead.
            let anchor = recordingAnchor ?? NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 24)
            let aboveY = anchor.y + panel.frame.height + 24
            let fitsAbove = aboveY + panel.frame.height <= visible.maxY
            let y = fitsAbove ? aboveY : anchor.y - panel.frame.height - 24
            panel.setFrameOrigin(NSPoint(x: anchor.x, y: max(y, visible.minY)))
        default:
            panel.setFrameOrigin(recordingAnchor ?? .zero)
        }
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        panel = nil
        panelHost = nil
    }

    /// Called from Rust callbacks when phase changes while panel may exist.
    func showPanelIfNeeded() {
        if panel != nil {
            resizePanelForCurrentState()
            positionPanelForCurrentState()
            panel?.orderFrontRegardless()
        }
    }
}

// MARK: - HUD Content

struct HUDContentView: View {
    @State private var model = AppModel.shared

    var body: some View {
        Group {
            switch model.phase {
            case .Recording:
                RecordingPillView(
                    audioLevel: model.audioLevel,
                    livePreview: model.partialTranscript,
                    livePreviewEnabled: model.livePreviewEnabled
                )

            case .Processing:
                TranscribingPillView()

            case .TranscriptReady:
                TranscriptOverlayView(
                    transcript: model.transcript,
                    copied: model.copied,
                    onCopy: { model.copyTranscript() },
                    onClose: { model.closeTranscript() }
                )
                .frame(width: 300)

            case .Error:
                ErrorView(
                    message: model.errorMessage,
                    onRetry: { model.retryRecording() },
                    onDismiss: { model.dismissTranscript() }
                )
                .frame(width: 300)

            case .Preparing:
                DownloadProgressView(
                    progress: model.downloadProgress,
                    speed: model.downloadSpeed,
                    remaining: model.downloadRemaining
                )
                .frame(width: 300)

            default:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.phase)
    }
}

// MARK: - Transcribing pill

struct TranscribingPillView: View {
    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.white.opacity(0.5))
                .padding(.leading, 14)

            Spacer(minLength: 2)

            WaveformView(audioLevel: 0.0)
                .frame(height: 20)
                .frame(maxWidth: 110)
                .opacity(0.5)

            Spacer(minLength: 2)

            Text("Transcribing")
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.trailing, 14)
        }
        .frame(width: 240, height: 44)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .compositingGroup()
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .scaleEffect(isVisible ? 1 : 0.85)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Error / Download views

struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.8))
            HStack {
                Button("Retry", action: onRetry)
                Spacer()
                Button("Dismiss", action: onDismiss)
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
    }
}

struct DownloadProgressView: View {
    let progress: Float
    let speed: String
    let remaining: String

    var body: some View {
        VStack(spacing: 10) {
            Text("Downloading Whisper model...")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            ProgressView(value: Double(progress))
                .progressViewStyle(.linear)
            if !speed.isEmpty {
                HStack {
                    Text(speed)
                    Spacer()
                    Text(remaining)
                }
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
    }
}
