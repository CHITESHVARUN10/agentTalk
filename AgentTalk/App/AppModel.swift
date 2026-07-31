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

    private var panel: NSPanel?
    private var panelHost: NSHostingView<HUDContentView>?
    private var recordingStartedAt: Date?

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

    /// Single entry point for starting dictation — used by hotkey AND menu.
    func startDictation() {
        print("[AgentTalk] startDictation — phase: \(phase), model: \(modelPhase)")
        guard phase == .Ready else {
            print("[AgentTalk] startDictation blocked — phase \(phase) not Ready")
            if modelPhase == .NotInstalled || modelPhase == .Downloading {
                showPanel() // show download progress
            }
            return
        }
        let ok = start_recording()
        print("[AgentTalk] start_recording returned: \(ok)")
        if ok {
            recordingStartedAt = Date()
            showPanel()
        }
    }

    func stopDictation() {
        guard phase == .Recording else { return }
        print("[AgentTalk] stopDictation")
        recordingStartedAt = nil
        stop_recording()
    }

    func copyTranscript() { copy_to_clipboard() }
    func pasteTranscript() { paste_into_frontmost_app() }

    func dismissTranscript() {
        dismiss_transcript()
        hidePanel()
    }

    func retryRecording() { retry_recording() }

    private func showPanel() {
        if panel != nil {
            panel?.makeKeyAndOrderFront(nil)
            return
        }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
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

        // Kill any window-level background: transparent content view
        p.contentView?.wantsLayer = true
        p.contentView?.layer?.backgroundColor = NSColor.clear.cgColor

        let host = NSHostingView(rootView: HUDContentView())
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 80)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        p.contentView = host

        // Bottom-center of screen
        if let screen = NSScreen.main {
            let sx = screen.visibleFrame.midX - 160
            let sy = screen.visibleFrame.minY + 40
            p.setFrameOrigin(NSPoint(x: sx, y: sy))
        } else {
            p.center()
        }

        panelHost = host
        panel = p
        p.orderFrontRegardless()
        print("[AgentTalk] Panel shown")
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        panel = nil
        panelHost = nil
    }
}

/// Observes AppModel directly — SwiftUI re-renders on model change.
struct HUDContentView: View {
    @State private var model = AppModel.shared

    var body: some View {
        Group {
            switch model.phase {
            case .Recording:
                RecordingPillView(audioLevel: model.audioLevel)
                    .frame(height: 52)
                    .padding(.horizontal, 8)

            case .Processing:
                ProcessingView()

            case .TranscriptReady:
                TranscriptOverlayView(
                    transcript: model.transcript,
                    onCopy: { model.copyTranscript() },
                    onRetry: { model.retryRecording() },
                    onDismiss: { model.dismissTranscript() }
                )
                .padding(8)

            case .Error:
                ErrorView(
                    message: model.errorMessage,
                    onRetry: { model.retryRecording() },
                    onDismiss: { model.dismissTranscript() }
                )
                .padding(8)

            case .Preparing:
                DownloadProgressView(
                    progress: model.downloadProgress,
                    speed: model.downloadSpeed,
                    remaining: model.downloadRemaining
                )
                .padding(8)

            default:
                EmptyView()
                .frame(width: 300, height: 60)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: model.phase)
    }
}

struct ProcessingView: View {
    var body: some View {
        HStack(spacing: 12) {
            ProgressView().scaleEffect(0.8)
            Text("Transcribing...")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: 240, height: 44)
        .background {
            RoundedRectangle(cornerRadius: 22)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
    }
}

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
