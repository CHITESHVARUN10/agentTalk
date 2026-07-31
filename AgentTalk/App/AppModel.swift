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

    private var panel: NSWindow?

    private init() {}

    func launch() {
        let ok = initialize_core()
        print("[AgentTalk] Core initialized: \(ok)")
        phase = get_app_phase()
        modelPhase = get_model_phase()

        Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { _ in
            Task { @MainActor in
                AppModel.shared.audioLevel = get_audio_level()
            }
        }
    }

    func handleHotkeyPress() -> Bool {
        guard phase == .Ready else { return false }
        let ok = start_recording()
        if ok { showPanel() }
        return ok
    }

    func handleHotkeyRelease() {
        guard phase == .Recording else { return }
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
        guard panel == nil else { panel?.makeKeyAndOrderFront(nil); return }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.contentView = NSHostingView(rootView: HUDContentView())
        p.center()
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    private func hidePanel() {
        panel?.orderOut(nil)
        panel = nil
    }
}

struct HUDContentView: View {
    @State private var phase: AppPhase = .Idle
    @State private var transcript: String = ""
    @State private var audioLevel: Float = 0.0
    @State private var downloadProgress: Float = 0.0
    @State private var downloadSpeed: String = ""
    @State private var downloadRemaining: String = ""
    @State private var errorMessage: String = ""

    private let model = AppModel.shared

    var body: some View {
        Group {
            switch phase {
            case .Recording:
                RecordingPillView(audioLevel: audioLevel)
                    .frame(height: 52)
                    .padding(.horizontal, 8)

            case .Processing:
                ProcessingView()

            case .TranscriptReady:
                TranscriptOverlayView(
                    transcript: transcript,
                    onCopy: { model.copyTranscript() },
                    onRetry: { model.retryRecording() },
                    onDismiss: { model.dismissTranscript() }
                )
                .padding(8)

            case .Error:
                ErrorView(
                    message: errorMessage,
                    onRetry: { model.retryRecording() },
                    onDismiss: { model.dismissTranscript() }
                )
                .padding(8)

            case .Preparing:
                DownloadProgressView(
                    progress: downloadProgress,
                    speed: downloadSpeed,
                    remaining: downloadRemaining
                )
                .padding(8)

            default:
                EmptyView()
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: phase)
        .onReceive(Timer.publish(every: 1.0/15.0, on: .main, in: .common).autoconnect()) { _ in
            phase = model.phase
            transcript = model.transcript
            audioLevel = model.audioLevel
            downloadProgress = model.downloadProgress
            downloadSpeed = model.downloadSpeed
            downloadRemaining = model.downloadRemaining
            errorMessage = model.errorMessage
        }
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
