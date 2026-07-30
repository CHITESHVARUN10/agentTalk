# Product Requirements Document
## macOS-Native AI Dictation Utility (MVP)

**Status:** Draft for build kickoff
**Owner:** Product/Engineering (single founder + collaborator)
**Last updated:** July 30, 2026

---

## 1. Overview & Vision

A macOS-native utility that converts spoken English into text, entirely on-device, as fast and accurately as possible. It is not a chatbot, not a meeting recorder, not an AI assistant — it is a single-purpose speed tool: **press a hotkey, talk, get text, keep working.**

Target feel: a system utility in the tradition of Spotlight or Raycast, not a "desktop application." Instant open, minimal UI, invisible until summoned, gone the moment it's done.

**North star:** the fastest way to type anywhere on macOS, usable dozens or hundreds of times a day without becoming a distraction itself.

---

## 2. Problem Statement

Existing options force a trade-off the user shouldn't have to make:

- **Apple's built-in dictation** — convenient but historically routes through Apple's servers for the higher-accuracy mode, and struggles with technical vocabulary, jargon, and code-adjacent terms.
- **Commercial cloud dictation tools** (Wispr Flow, Willow Voice, and similar) — good accuracy and UX, but recurring subscriptions ($8–15/month is typical in this category) and audio leaving the device.
- **General-purpose AI assistants** — overkill: they carry chat, memory, and orchestration weight for a task that is fundamentally "microphone in, text out."

The gap: a **free, local-only, fast, single-purpose** dictation utility that treats speed and privacy as the entire feature set rather than a footnote.

---

## 3. Goals & Non-Goals

### In scope (MVP)
| Capability | Included |
|---|---|
| English speech → text | ✅ |
| Fully local inference (no network calls) | ✅ |
| Global keyboard shortcut to trigger | ✅ |
| Small floating recording panel | ✅ |
| Copy to clipboard | ✅ |
| Auto-paste into active application | ✅ |
| Retry / discard | ✅ |

### Explicitly out of scope (MVP)
- Translation, multi-language support
- Chat or conversational features
- Meeting/long-form transcription
- AI rewriting, grammar correction, summarization
- Voice commands / assistant behaviors
- Multiple simultaneous transcription models

This narrow scope is deliberate. Every open-source competitor reviewed in Section 5 that tried to be "dictation + AI cleanup + multi-provider" ended up materially more complex to build and maintain than the pure dictation tools. Staying narrow is the actual strategy, not a placeholder for "not done yet."

### Non-goal for now: cross-platform
Rust-as-core keeps a cross-platform core theoretically possible later, but Windows/Linux support is not a design constraint for MVP decisions (UI framework, packaging, permissions model). Don't let "someday cross-platform" water down macOS-native quality now.

---

## 4. Target User & Primary Use Cases

- Developers and technical writers who dictate into terminals, IDEs, Slack, email, and docs and need technical terms transcribed correctly.
- Users who dictate frequently (dozens of times/day) and are sensitive to latency — a 3–5 second delay per dictation compounds fast at that frequency.
- Privacy-conscious users who won't send audio to a third-party server as a matter of policy, not just preference.

Primary use cases: quick Slack/email replies, commit messages and code comments, note capture, filling text fields anywhere in macOS without switching context to a "real" app.

---

## 5. Competitive & Open-Source Landscape

This space is more crowded with open-source prior art than expected — worth building on top of rather than starting from zero. Grouped by what's reusable.

### 5.1 Direct prior art — whisper.cpp-based macOS dictation apps
These validate the exact architecture pattern (global hotkey → whisper.cpp + Metal → paste) and are worth reading for implementation details, UX patterns, and pitfalls already solved by others:

- **WhisperDictation** (`sam-pop/WhisperDictation`) — free/local macOS dictation app, whisper.cpp + Metal, explicitly positions itself against Willow Voice/Wispr Flow. Push-to-talk *and* toggle mode, with a debounce on toggle mode to avoid accidental activation — a UX detail worth copying directly.
- **OpenSuperWhisper** (`Starmel/OpenSuperWhisper`, MIT, also forked as `shaneholloman/open-super-whisper`) — mature reference implementation: real-time recording, two swappable STT engines (Whisper + Parakeet), global hotkeys including single-modifier keys (Left ⌘, Right ⌥, Fn), mouse-button triggers, hold-to-record, drag-and-drop file transcription, mic source switching (built-in/external/Bluetooth/Continuity). This is probably the single best reference codebase for the MVP.
- **WhisperApp** (`Gamezxz/WhisperApp`) — menu-bar app, Fn-key hold-to-talk, live waveform + status overlay (recording → transcribing → fixing → done) — good state-machine reference for the floating panel.
- Multiple smaller MIT/Swift menu-bar dictation apps surfaced under the `whisper-cpp` and `whisper` GitHub topics, several explicitly built with WhisperKit (Apple-Silicon-only Swift/CoreML implementation) instead of whisper.cpp — worth a skim for the WhisperKit-vs-whisper.cpp trade-off, covered in Section 9.

### 5.2 Cross-platform / broader-scope alternatives (borrow ideas, not architecture)
- **OpenWhispr** (`OpenWhispr/openwhispr`) — cross-platform (macOS/Windows/Linux), local Whisper/Parakeet + optional cloud BYOK, adds meeting transcription and "AI agents." Useful for seeing where scope creep leads — this is the shape of app the MVP is deliberately *not* building.
- **mlx-whisper-dictation** (`computerstimulation/mlx-whisper-dictation`) — same dictation concept, MLX backend instead of whisper.cpp. Directly relevant to the Section 9 backend decision.

### 5.3 Rust building blocks (library-level reuse, not whole apps)
- **whisper-rs** (`tazz4843/whisper-rs`, also mirrored at Codeberg) — the standard, actively maintained Rust binding to whisper.cpp. ~115K downloads/month, used in ~79 crates. This is the default choice for the inference layer (Section 9/10).
- **mutter** (`sigaloid/mutter`) — thin wrapper over whisper-rs that adds arbitrary-audio-format decoding via `rodio`, so the Rust core doesn't have to hand-roll WAV/PCM conversion.
- **whisper-cpp-plus-rs** (`operator-kit/whisper-cpp-plus-rs`) — adds real-time PCM streaming and Silero VAD integration on top of whisper-rs; relevant if streaming/partial-result transcription becomes a later goal.
- **voice_activity_detector** / **silero-vad-rs** / **vad-silero-rs** — several independent, actively maintained Rust ports of Silero VAD (ONNX-based). Any of these can auto-detect "user stopped talking" to end a recording without requiring a manual stop press — worth evaluating as a v1.1 UX improvement even if not MVP-critical.
- **swift-bridge** (`chinedufn/swift-bridge`) and **UniFFI** (via `cargo-swift`) — the two mature options for the Rust ↔ Swift FFI boundary. See Section 10 for the recommendation.

### 5.4 What to explicitly avoid copying
- Multi-provider STT switching (ElevenLabs/OpenAI/Groq/whisper.cpp in one app) — adds a settings surface and API-key management the MVP philosophy rejects.
- "AI text correction" post-processing steps bundled into the core flow — reintroduces cloud dependency (most of these use a hosted LLM) and violates the offline-only requirement unless it's a genuinely optional, clearly-labeled, off-by-default feature much later.

---

## 6. User Experience & Flow

### 6.1 Happy path
```
Idle (menu bar icon, no window)
   │  user presses global hotkey
   ▼
Floating panel appears near bottom of screen, recording starts immediately
   │  user speaks
   │  user presses hotkey again / releases (push-to-talk) to stop
   ▼
Panel shows "Processing" state (brief, ideally < 1s perceived)
   ▼
Transcript shown in panel
   │  user chooses:
   ├─ Copy → clipboard, panel closes
   ├─ Paste → auto-paste into last-focused app, panel closes
   ├─ Retry → discard, re-record
   └─ Close/Discard → panel closes, nothing kept
```

### 6.2 Edge cases the PRD needs to force a decision on before build
These are the details that make dictation tools feel broken if unhandled — each needs an explicit answer, not "we'll see":

1. **No speech detected / silence-only recording.** Show a clear "didn't catch that" state with a Retry button rather than pasting an empty string or a hallucinated phrase (Whisper is known to hallucinate short phrases on silence/noise-only input — this is a documented failure mode, not an edge case to ignore).
2. **Accessibility permission not yet granted.** Auto-paste requires either Accessibility (CGEvent post) or a similarly privileged permission (see Section 12). First-launch flow must detect this, explain *why* it's needed in one sentence, and deep-link to System Settings. The system permission prompt can only be shown once per launch — if dismissed, the app must guide the user to Settings manually, not just retry silently.
3. **No focused text field when paste fires.** Fall back to clipboard-only with a subtle confirmation, never silently fail.
4. **Hotkey held/pressed while the panel is already open (retry loop, double-trigger).** Define whether a second hotkey press while recording stops-and-transcribes, cancels, or is ignored — pick one behavior and make it consistent across push-to-talk and toggle modes.
5. **App switch mid-recording.** If the user alt-tabs away mid-dictation, paste-on-completion must target whichever app was focused *before* the hotkey was pressed, not whatever is focused when transcription finishes.
6. **Very long dictation.** Decide a soft cap (e.g., visual warning past ~60–90s) since this is explicitly a short-dictation tool, not a meeting recorder — an unbounded recording buffer works against the "narrow scope" philosophy and against Turbo's short-form design point.
7. **Model not yet loaded (first run / cold start after quit).** Show a one-time "warming up" state rather than a hotkey press that appears to do nothing.
8. **Multiple displays / full-screen apps.** Decide which screen the panel appears on (active display vs. primary display) and whether it can appear over a full-screen app (this needs a specific `NSWindow.Level` / space-behavior decision, not just "it'll work").

---

## 7. System Architecture

```
┌─────────────────────────────┐
│   SwiftUI (thin UI layer)   │  floating panel, menu bar item, permission prompts
└───────────────┬─────────────┘
                │  FFI boundary (Section 10)
┌───────────────▼─────────────┐
│         Rust Core            │  state machine, audio capture, model
│  ─────────────────────────   │  lifecycle, inference invocation,
│  • Recording/session state    │  clipboard + paste, hotkey handling
│  • Model loading & caching    │
│  • Inference (whisper-rs)     │
│  • Clipboard / auto-paste     │
│  • Global hotkey (if in Rust) │
└───────────────┬─────────────┘
                │
┌───────────────▼─────────────┐
│  whisper.cpp (Metal-accel.)  │  see Section 9 for backend decision
└──────────────────────────────┘
```

**Principle carried over from the source spec:** SwiftUI knows nothing about Whisper internals — it only calls into a Rust API surface (start recording, stop recording, get transcript, copy, paste, retry). This keeps the UI replaceable and the business logic testable independent of SwiftUI.

### 7.1 Recommended module boundaries (Rust core)
- `audio` — mic capture via `cpal`, resampling to 16kHz mono f32 (Whisper's required input format)
- `vad` (optional, v1.1) — Silero VAD integration for auto-stop-on-silence
- `inference` — whisper-rs wrapper: model loading, warm-up, `full()` invocation, segment extraction
- `state` — the session state machine (idle → recording → processing → transcript → done), the single source of truth the UI observes
- `system` — clipboard (`arboard`), paste simulation (CGEvent via `core-graphics` crate), Accessibility-permission checks
- `hotkey` — global shortcut registration (see Section 12 for the CGEventTap-vs-Carbon trade-off)

---

## 8. Speech Recognition Model: Whisper Large-v3-Turbo

Confirming and grounding the existing decision with current numbers:

- **Turbo is a pruned/distilled large-v3**: decoder layers reduced from 32 to 4, cutting parameters from 1.55B (large-v3) to 809M. It was fine-tuned for two additional epochs on the same multilingual data after pruning (not just distilled from scratch), which is why it recovers most of large-v3's quality despite the aggressive layer cut.
- **Speed**: community consensus puts turbo at roughly 6–8x faster inference than large-v3, with an accuracy gap generally under 1 WER point on English audio (larger degradation is reported specifically for Thai and Cantonese, which don't apply to an English-only MVP).
- **Memory**: turbo's GGML/quantized model file lands well under large-v3's ~2.9GB, with runtime memory correspondingly lower — consistent with the original decision's stated rationale ("lower memory than Large").
- **Why not Medium**: Medium (769M params) is close to Turbo (809M) in raw size but Turbo's distillation-from-large-v3 lineage gives it a real accuracy edge for the same latency budget — this is well-supported by the current benchmarks and confirms the existing call.

**Verdict: keep Turbo.** It's the correct point on the speed/accuracy curve for "dozens of short dictations per day," and it's the model most of the reviewed open-source prior art (Section 5) has converged on for the same reason.

One open item worth flagging for the model-selection UI (even if not user-facing in MVP): turbo's English-only accuracy is strong enough that shipping the English-only Whisper checkpoint variant (rather than the multilingual one) is worth evaluating if/when an English-only turbo checkpoint is available, since it would shave additional memory with zero functional loss for this MVP's English-only scope.

---

## 9. Inference Backend: whisper.cpp vs MLX — Resolving the Pending Decision

This was the one open architectural question in the source spec. Recommendation below, with the reasoning shown so it can be revisited if a benchmark changes.

### 9.1 What the research shows
- Benchmarks are **inconsistent and implementation-dependent**, not a clean win for either side:
  - One community test (M1 Pro, large-v2 @ 8-bit) found whisper.cpp *faster* than vanilla mlx-whisper (~1m vs ~1m36s).
  - A follow-up test with better methodology found mlx-whisper 30–40% faster on the same hardware class.
  - `lightning-whisper-mlx` claims up to 10x whisper.cpp's speed — but that's a heavily optimized, batched-decoding, Python-only project, not the baseline `mlx-whisper` — it's a different comparison than "MLX vs whisper.cpp" as architectures.
  - A 2026 comparison piece explicitly recommends whisper.cpp for all Mac speech-to-text work, citing its Metal backend's unified-memory advantage and Core ML Neural-Engine encoder offload as the more mature, more consistently fast path.
- **Metal-accelerated whisper.cpp benchmarks (2026 community data)**: ~7x realtime on M3, ~10x realtime on M5 Pro for large-v3, with Core ML encoder export giving further headroom on top of plain Metal. Turbo would sit well above these multiples given its lower parameter count.

### 9.2 What matters more than raw benchmark speed, given this project's constraints
- **MLX has no first-class Rust binding.** The MLX ecosystem is Python-first, with an official Swift binding (MLX Swift) — there is no mature MLX Rust crate comparable to whisper-rs's maturity (114K downloads/month, 79 dependent crates). Adopting MLX would mean either:
  - (a) doing inference in Swift and having Swift, not Rust, own model lifecycle/inference — which contradicts the "Rust core owns the business logic, SwiftUI is thin" architecture already decided, or
  - (b) writing and maintaining a bespoke Rust↔MLX-C++ FFI layer — real work with no existing prior art to build on, for a benchmark advantage that isn't even consistent across tests.
- **whisper.cpp's Rust path is a solved problem.** whisper-rs is mature, widely used, and already supports Metal + CUDA + Core ML flags — it fits directly into the Rust-core architecture with no new FFI surface beyond what's already planned for Swift↔Rust (Section 10).
- **Every comparable open-source macOS dictation app found in Section 5 that ships today uses whisper.cpp**, not MLX, for exactly this reason: it's the path with mature tooling at every layer (model format, Rust bindings, Metal acceleration, Core ML encoder offload) rather than the path with the best benchmark number in one specific test.

### 9.3 Recommendation
**Use whisper.cpp via whisper-rs**, with Metal acceleration enabled and Core ML encoder offload evaluated as a fast-follow optimization once the MVP pipeline works end-to-end. Revisit MLX only if a first-class, actively-maintained Rust MLX binding emerges, or if the Rust-core architectural decision itself changes.

This closes the one item the source spec marked "not yet finalized" — everything else in the architecture can now be treated as settled going into build.

---

## 10. Rust ↔ Swift Interop

Two viable, actively maintained options surfaced:

| | swift-bridge | UniFFI (+ `cargo-swift`) |
|---|---|---|
| Origin | Rust-community project purpose-built for Rust↔Swift | Mozilla project, Rust↔multi-language (Swift, Kotlin, Python…) |
| Type support | Rich: shares `Option<T>`, `String`, structs, classes, async, generics directly | Interface-description-based; slightly more boilerplate for complex shared types |
| Best fit here | Tight, bidirectional calls (Swift calling into Rust *and* Rust calling back into Swift, e.g. for UI state callbacks) | Simpler one-directional "Swift calls Rust" APIs; better if cross-platform (Kotlin/Windows) reuse is ever wanted |

**Recommendation:** `swift-bridge`, because the app needs Rust to call back into Swift (e.g., pushing state-machine updates like "processing" → "transcript ready" to the SwiftUI layer), not just one-directional calls. If the project later wants to share the Rust core with a hypothetical Windows/Linux UI, UniFFI's multi-language story becomes more attractive — worth a note in the roadmap, not a blocker now.

---

## 11. Audio Capture & Voice Activity Detection

- **Capture:** `cpal` is the standard cross-platform Rust audio crate and the natural fit for the Rust-owns-audio architecture; it wraps Core Audio on macOS.
- **Format:** resample to 16kHz mono 32-bit float — Whisper's required input format — in the Rust core before handing buffers to whisper-rs.
- **VAD (recommended for v1.1, not MVP-blocking):** Silero VAD has multiple independent, maintained Rust ports (`voice_activity_detector`, `silero-vad-rs`, `vad-silero-rs`), all ONNX-based. Adding VAD later enables auto-stop-on-silence (no second hotkey press needed) and could suppress the "hallucinated transcript on silence" failure mode from Section 6.2 by skipping inference entirely on silent buffers.

---

## 12. Global Hotkey, Auto-Paste & System Permissions

This section deserves more weight than the source spec gave it — it's where most shipped dictation apps hit real friction, and it directly affects the distribution decision in Section 13.

### 12.1 Hotkey capture: two real options, a real trade-off
- **Carbon `RegisterEventHotKey`** — works with zero entitlements/permission prompts, even sandboxed. But it's a legacy API with known edge cases: it can silently fail to fire inside apps with custom-drawn views (self-drawn terminals like Zed's or VS Code's built-in terminal have been reported not to receive Carbon-registered hotkeys).
- **CGEventTap (Quartz Event Services)** — reliably captures/consumes events everywhere, including custom-drawn terminal views, but requires the Accessibility permission prompt.
- Recommendation: **CGEventTap**, accepting the Accessibility-permission requirement, because reliability of the hotkey firing in *every* app (including terminals and IDEs — this tool's core audience) matters more than avoiding one permission prompt. A hybrid fallback (Carbon primary, CGEventTap as an opt-in "make this more reliable" toggle) is a reasonable compromise if minimizing the permission ask is a priority later.

### 12.2 Auto-paste mechanism
Standard, working pattern from current implementations: write text to `NSPasteboard`/clipboard, then simulate ⌘V via `CGEvent.post`, then (optionally, after a short delay) restore whatever was on the clipboard before. This requires the same Accessibility/`kTCCServicePostEvent` permission as the hotkey.

### 12.3 Permission UX
- Check `AXIsProcessTrusted()` (or equivalent) on launch; if not granted, show a one-time, plain-language explanation *before* triggering the system prompt (the system prompt itself only shows once per launch if dismissed — burning it on a confusing moment is a real cost).
- Always provide a manual path to System Settings → Privacy & Security → Accessibility, since a dismissed/denied prompt requires an app restart to reappear automatically.

### 12.4 Important distribution implication — surfaced here because it changes Section 13
Apple has rejected at least one sandboxed Mac App Store submission under Guideline 2.4.5 specifically for using `CGEvent.post` to simulate a paste keystroke, on the reasoning that Accessibility-tier APIs shouldn't be used for non-accessibility purposes — even though the technical permission involved (`kTCCServicePostEvent`) is distinct from the Accessibility API family (`AXUIElement`) and both merely surface under the same System Settings pane. This is a real App Store risk for this exact feature (auto-paste-anywhere), not a hypothetical one.

---

## 13. Distribution & Packaging

Given Section 12.4, this needs an explicit decision rather than defaulting to "we'll submit to the App Store later":

| | Direct distribution (notarized .app/.dmg, outside App Store) | Mac App Store |
|---|---|---|
| Global hotkey + auto-paste-anywhere | Fully supported, no sandbox restrictions | Real rejection risk (Guideline 2.4.5 precedent above); may require framing/justification or removing auto-paste |
| Distribution effort | Requires own notarization pipeline (`notarytool`), Developer ID certificate, update mechanism (e.g., Sparkle) | Apple handles hosting/updates, but review risk on the core feature |
| Trust/discoverability | Lower trust by default (Gatekeeper "unidentified developer" friction unless notarized) | Higher baseline trust |

**Recommendation:** build and ship as a **notarized, direct-distribution app** for MVP. The core feature — reliable auto-paste into *any* app, anywhere — is exactly the feature category with documented App Store rejection precedent. Revisit an App Store submission later only if the paste mechanism is reworked in a way that satisfies review (e.g., clipboard-only mode as the App Store SKU, direct-distribution build keeping auto-paste).

---

## 14. Non-Functional Requirements

- **Perceived latency budget:** hotkey press → panel visible: effectively instant (<100ms). Recording stop → transcript visible: this is the number that defines "feels fast" — target well under 2 seconds for a 10–15 second dictation on Apple Silicon, which Turbo + Metal-accelerated whisper.cpp comfortably supports based on the RTF figures in Section 9.
- **Memory:** model resident in memory only while the app is active/recently used; define an idle-unload timeout so the app doesn't hold ~1–2GB resident indefinitely for a tool meant to be "always available." (This mirrors a real constraint already hit on the related JarvisMacOS project, where a resident large model pushed the system into swap — worth designing around proactively here rather than discovering it the same way.)
- **Battery/CPU:** Metal GPU inference keeps CPU cores free during transcription — validated by the whisper.cpp Metal benchmarks in Section 9 — but idle-state CPU usage (menu bar app, hotkey listener) should be verified near-zero; a global CGEventTap listener running constantly is cheap but not free, and should be profiled.
- **Accuracy target:** English WER competitive with large-v2 on clean audio per Section 8 figures; no formal internal benchmark needed for MVP beyond manual testing across accents/technical vocabulary the target user actually uses.
- **Privacy:** zero network calls during the recording→transcript path — this should be enforced structurally (e.g., no network entitlement / explicit code-level assertion), not just a stated policy, since it's the product's core differentiator.

---

## 15. Risks & Open Questions

1. **App Store rejection risk (Section 12.4/13)** — needs a firm distribution decision before investing in a submission pipeline.
2. **CGEventTap reliability across third-party apps** — the Zed/VS-Code-terminal failure mode (Section 12.1) means hotkey behavior needs explicit testing in self-drawn-UI apps, not just standard Cocoa text fields.
3. **Whisper hallucination on silence/noise** (Section 6.2) — needs either VAD (Section 11) or a confidence/energy-based guard before MVP ships, or short dictations in noisy environments will produce confidently-wrong text with no error signal to the user.
4. **Model bundling size** — decide whether the Turbo model ships inside the app bundle (~800MB–1.5GB depending on quantization) or downloads on first launch; affects notarized `.dmg` size and first-run experience.
5. **Core ML encoder offload** — not evaluated in depth here; flagged in Section 9.3 as a fast-follow, not a blocker, but worth a spike early since it's a meaningful additional speed lever on top of Metal alone.

---

## 16. Suggested Build Phases

1. **Spike:** whisper-rs + Metal, transcribing a pre-recorded WAV, to validate the Turbo-model latency numbers on the actual target hardware before committing further.
2. **Rust core skeleton:** state machine + `cpal` capture + whisper-rs inference, callable from a throwaway CLI (no SwiftUI yet) — proves the core pipeline independent of UI/FFI complexity.
3. **Swift↔Rust FFI wiring** (swift-bridge, Section 10) + minimal SwiftUI panel driven by Rust state.
4. **Hotkey + paste integration** (Section 12), including the permission-prompt UX.
5. **Edge-case pass** against the full list in Section 6.2.
6. **Notarized packaging** (Section 13) and distribution pipeline.
7. **(Fast-follow) VAD auto-stop + Core ML encoder offload.**

---

## 17. Open-Source Prior Art — Reference List

| Project | Link | Relevance |
|---|---|---|
| WhisperDictation | github.com/sam-pop/WhisperDictation | Closest architectural match; push-to-talk/toggle UX |
| OpenSuperWhisper | github.com/Starmel/OpenSuperWhisper | Best overall reference implementation |
| WhisperApp | github.com/Gamezxz/WhisperApp | Menu-bar state machine, hotkey UX |
| OpenWhispr | github.com/OpenWhispr/openwhispr | Cautionary example of scope creep |
| mlx-whisper-dictation | github.com/computerstimulation/mlx-whisper-dictation | MLX-backend comparison point |
| whisper-rs | github.com/tazz4843/whisper-rs (mirror: codeberg.org/tazz4843/whisper-rs) | Core Rust↔whisper.cpp binding |
| mutter | github.com/sigaloid/mutter | Audio-format handling on top of whisper-rs |
| whisper-cpp-plus-rs | github.com/operator-kit/whisper-cpp-plus-rs | Streaming + VAD reference |
| voice_activity_detector | crates.io/crates/voice_activity_detector | Silero VAD in Rust |
| swift-bridge | github.com/chinedufn/swift-bridge | Rust↔Swift FFI |
| cargo-swift (UniFFI) | github.com/antoniusnaumann/cargo-swift | Alternative FFI path |
| whisper.cpp | github.com/ggerganov/whisper.cpp | Underlying inference engine |

---

## Appendix: Current Decisions (carried over, one item resolved)

| Component | Decision |
|---|---|
| Platform | macOS only |
| UI | SwiftUI |
| Backend | Rust |
| Cloud | No |
| Offline | Yes |
| Language Support | English only |
| Primary Feature | Speech → Text |
| Model | Whisper Turbo |
| Translation | No |
| Meeting Recording | No |
| AI Rewriting | No |
| Architecture | SwiftUI → Rust → whisper.cpp (Metal) |
| Inference Backend | **whisper.cpp via whisper-rs** *(resolved in Section 9 — was pending)* |
| Rust↔Swift FFI | **swift-bridge** *(new — resolved in Section 10)* |
| Hotkey mechanism | **CGEventTap** *(new — resolved in Section 12.1)* |
| Distribution | **Direct/notarized, not App Store, for MVP** *(new — resolved in Section 13)* |
