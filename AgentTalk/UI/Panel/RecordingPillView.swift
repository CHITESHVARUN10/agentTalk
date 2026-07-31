import SwiftUI

/// Recording pill — the primary HUD element shown during dictation.
/// Refined from the Stitch "Whisper Flow" Classic HUD design system.
///
/// Philosophy: Apple Spotlight / HUD / Dynamic Island / Voice Memos.
/// This is a reassurance indicator — not a feature surface.
/// The user continues working while this gently confirms recording is active.
///
/// Design tokens sourced from the Stitch project:
/// - Pill: 240×44px, fully rounded (22px corner radius)
/// - Glass: Ultra Thin Material + blur(24px) saturate(180%)
/// - Border: 0.5px white at 12% opacity
/// - Shadow: 20px blur, 40% black, 10px Y offset
/// - Dot: 8px #ba1a1a with 6px red glow, breathing pulse
/// - Waveform: organic, calm, white 55% opacity
/// - Type: Inter, 11px medium, 40% white
struct RecordingPillView: View {
    @State private var isVisible = false
    var audioLevel: Float = 0.2

    var body: some View {
        HStack(spacing: 10) {
            // Recording status dot — breathing room from left edge
            RecordingStatusDot()
                .padding(.leading, 14)

            Spacer(minLength: 2)

            WaveformView(audioLevel: audioLevel)
                .frame(height: 20)
                .frame(maxWidth: 110)

            Spacer(minLength: 2)

            Text("Recording")
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

/// 8px red status dot with soft glow and breathing pulse.
/// Communicates "recording active" with zero cognitive load.
private struct RecordingStatusDot: View {
    @State private var isPulsing = false

    private let dotColor = Color(red: 0.73, green: 0.10, blue: 0.10)

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 8, height: 8)
            .shadow(color: dotColor.opacity(0.6), radius: 6)
            .opacity(isPulsing ? 0.55 : 1.0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.6)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            }
    }
}

// MARK: - Transition to Transcript State

/// Extends the recording pill to show the transcript after recording ends.
/// Uses the same glass panel aesthetic, expanding from 44px → auto height.
struct TranscriptOverlayView: View {
    let transcript: String
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onDismiss: () -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Transcript text
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    Text(transcript)
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        TranscriptButton(title: "Copy", icon: "doc.on.doc", action: onCopy)
                        TranscriptButton(title: "Retry", icon: "arrow.counterclockwise", action: onRetry)
                        Spacer()
                        TranscriptButton(title: "Done", icon: "checkmark", action: onDismiss, isPrimary: true)
                    }
                }
                .padding(16)
                .transition(
                    .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .move(edge: .top))
                    )
                )
            }
        }
        .frame(minWidth: 240)
        .background {
            RoundedRectangle(cornerRadius: isExpanded ? 16 : 22)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            RoundedRectangle(cornerRadius: isExpanded ? 16 : 22)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: isExpanded ? 16 : 22))
        .compositingGroup()
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                isExpanded = true
            }
        }
    }
}

private struct TranscriptButton: View {
    let title: String
    let icon: String
    let action: () -> Void
    var isPrimary: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background {
                if isPrimary {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.white.opacity(0.15))
                }
            }
            .foregroundStyle(isPrimary ? .white : .white.opacity(0.6))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Recording") {
    ZStack {
        Color(red: 0.11, green: 0.11, blue: 0.12).ignoresSafeArea()

        VStack {
            Spacer()
            RecordingPillView()
                .padding(.bottom, 60)
        }
    }
}

#Preview("Transcript") {
    ZStack {
        Color(red: 0.11, green: 0.11, blue: 0.12).ignoresSafeArea()

        VStack {
            Spacer()
            TranscriptOverlayView(
                transcript: "This is a sample transcript. The user spoke these words and they appear here after processing.",
                onCopy: {},
                onRetry: {},
                onDismiss: {}
            )
            .padding(.bottom, 60)
        }
    }
}
