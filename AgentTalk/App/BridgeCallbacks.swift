import AppKit
import SwiftUI

func on_state_changed(phase: AppPhase, model: ModelPhase) {
    DispatchQueue.main.async {
        let app = AppModel.shared
        app.phase = phase
        app.modelPhase = model

        if phase == .Processing || phase == .TranscriptReady {
            app.showPanelIfNeeded()
        }

        if phase == .TranscriptReady {
            app.transcript = get_transcript().toString()
        }

        // A press during model load is queued; fire it now that Ready arrived.
        if phase == .Ready {
            app.flushPendingStart()
        }
    }
}

func on_transcript_ready(text: RustString) {
    let t = text.toString()
    DispatchQueue.main.async {
        AppModel.shared.transcript = t
        AppModel.shared.partialTranscript = ""
        AppModel.shared.phase = .TranscriptReady
    }
}

func on_partial_transcript(text: RustString) {
    let t = text.toString()
    DispatchQueue.main.async {
        let app = AppModel.shared
        app.partialTranscript = t
        // Panel may need to grow to fit the preview bubble above the pill
        app.showPanelIfNeeded()
    }
}

func on_error(message: RustString) {
    let msg = message.toString()
    print("[AgentTalk] Error: \(msg)")
    DispatchQueue.main.async {
        AppModel.shared.errorMessage = msg
        AppModel.shared.phase = .Error
    }
}

func on_download_progress(progress: Float, speed: RustString, remaining: RustString) {
    DispatchQueue.main.async {
        let app = AppModel.shared
        app.downloadProgress = progress
        app.downloadSpeed = speed.toString()
        app.downloadRemaining = remaining.toString()
    }
}
