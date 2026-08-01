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
    var livePreview: String = ""
    var livePreviewEnabled: Bool = false

    var body: some View {
        // Column: optional live-preview bubble above, pill below.
        // The pill itself is unchanged — waveform always visible.
        // The column widens to 400 when the preview is showing so the
        // bubble has room for readable text; the pill stays 240 centered.
        VStack(spacing: 6) {
            if livePreviewEnabled && !livePreview.isEmpty {
                LivePreviewBubble(text: livePreview)
            }

            pill
        }
        .frame(width: previewVisible ? 400 : 240)
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .scaleEffect(isVisible ? 1 : 0.85)
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isVisible = true
            }
        }
    }

    private var previewVisible: Bool {
        livePreviewEnabled && !livePreview.isEmpty
    }

    private var pill: some View {
        HStack(spacing: 10) {
            // Recording status dot — breathing room from left edge
            RecordingStatusDot()
                .padding(.leading, 14)

            Spacer(minLength: 2)

            // Waveform always present — never replaced
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
    }
}

/// Glass bubble above the pill showing the live transcript so far.
/// Wider than the pill so the preview is actually readable.
/// Same material/border language as the pill.
private struct LivePreviewBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .regular, design: .default))
            .foregroundStyle(.white.opacity(0.75))
            .lineLimit(3)
            .truncationMode(.tail)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: 400, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 14)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .stroke(.white.opacity(0.12), lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .compositingGroup()
            .transition(.opacity.combined(with: .move(edge: .bottom)))
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

// MARK: - Transcript State

/// Transcript panel — same glass language, expands above the pill position.
/// Exactly two actions: Copy and Close.
/// Text area scrolls when long; buttons stay pinned at the bottom.
/// Total height is capped so the window never grows past the screen.
struct TranscriptOverlayView: View {
    let transcript: String
    var copied: Bool = false
    let onCopy: () -> Void
    let onClose: () -> Void

    @State private var isExpanded = false
    @State private var showCheck = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Scrollable text — capped height, grows only inside this box
            ScrollView {
                Text(transcript)
                    .font(.system(size: 14, weight: .regular, design: .default))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 96)

            Divider()
                .overlay(.white.opacity(0.1))

            HStack(spacing: 8) {
                // Copy — primary
                Button(action: {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        showCheck = true
                    }
                    onCopy()
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                        Text(copied ? "Copied" : "Copy")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.white.opacity(0.15))
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .scaleEffect(showCheck ? 1.05 : 1.0)

                Spacer()

                // Close — secondary
                Button(action: onClose) {
                    HStack(spacing: 5) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                        Text("Close")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(width: 300, height: 170)
        .background {
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .stroke(.white.opacity(0.12), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .compositingGroup()
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
        .scaleEffect(isExpanded ? 1 : 0.9)
        .opacity(isExpanded ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                isExpanded = true
            }
        }
    }
}

// MARK: - Placement Dummy Pill

/// Draggable dummy pill shown when the user is choosing a custom position.
/// Same glass language as the recording pill; checkmark confirms the spot.
struct PlacementPillView: View {
    let onConfirm: () -> Void

    @State private var isVisible = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.draw")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.leading, 16)

            Spacer(minLength: 2)

            Text("Drag to position")
                .font(.system(size: 11, weight: .medium, design: .default))
                .foregroundStyle(.white.opacity(0.5))

            Spacer(minLength: 2)

            // Checkmark — confirm this position
            Button(action: onConfirm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(.trailing, 14)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
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
                onClose: {}
            )
            .padding(.bottom, 60)
        }
    }
}
