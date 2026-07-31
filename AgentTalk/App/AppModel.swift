import SwiftUI
import Observation
import AppKit

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    var phase: AppPhase = .Idle
    var modelPhase: ModelPhase = .NotInstalled
    var transcript: String = ""
    var errorMessage: String = ""
    var downloadProgress: Float = 0.0
    var downloadSpeed: String = ""
    var downloadRemaining: String = ""
    var audioLevel: Float = 0.0
    var copied = false

    private var panel: NSPanel?
    private var panelHost: NSHostingView<HUDContentView>?
    private var recordingStartedAt: Date?
    private var lastVisibleFrame: NSRect?
    private var pendingStartOnReady = false

    private init() {}

    func launch() {
        let ok = initialize_core()
        print("[AgentTalk] Core initialized: \(ok)")
        phase = get_app_phase()
        modelPhase = get_model_phase()
        print("[AgentTalk] Initial phase: \(phase), model: \(modelPhase)")

        Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.audioLevel = get_audio_level()
        }

        // Max recording duration watchdog — auto-stops at 90s cap
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.phase == .Recording else { return }
            let elapsed = self.recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            if elapsed > 90 {
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
        case .Idle, .Preparing:
            // Model still loading/downloading. Queue a start for when Ready
            // arrives so the press is not lost, and show preparation feedback.
            print("[State] Model not ready — queuing start on Ready")
            pendingStartOnReady = true
            showPanel()
        default:
            // Processing, TranscriptReady, Error
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
            showPanel()
        }
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
        p.isMovable = false

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
        case .Recording, .Processing:
            return CGSize(width: 240, height: 44)
        case .TranscriptReady:
            return CGSize(width: 300, height: 140)
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
        let frame = panel.frame
        let visible = screen.visibleFrame

        switch phase {
        case .TranscriptReady:
            let y = visible.minY + 120
            panel.setFrameOrigin(NSPoint(x: visible.midX - frame.width/2, y: y))
        default:
            let y = visible.minY + 24
            panel.setFrameOrigin(NSPoint(x: visible.midX - frame.width/2, y: y))
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
                RecordingPillView(audioLevel: model.audioLevel)
                    .frame(width: 240, height: 44)

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
