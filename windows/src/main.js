const { invoke } = window.__TAURI__?.core ?? { core: { invoke: async () => {} } };

const pill = document.getElementById("pill");
const transcribing = document.getElementById("transcribing");
const transcriptCard = document.getElementById("transcript");
const transcriptText = document.getElementById("transcript-text");
const errorCard = document.getElementById("error");
const errorText = document.getElementById("error-text");
const wave = document.getElementById("wave");

function setState(state) {
  pill.classList.add("hidden");
  transcribing.classList.add("hidden");
  transcriptCard.classList.add("hidden");
  errorCard.classList.add("hidden");
  if (state === "Recording") pill.classList.remove("hidden");
  else if (state === "Processing") transcribing.classList.remove("hidden");
  else if (state === "TranscriptReady") transcriptCard.classList.remove("hidden");
  else if (state === "Error") errorCard.classList.remove("hidden");
  else if (state === "Preparing") transcribing.classList.remove("hidden");
}

document.getElementById("btn-copy")?.addEventListener("click", async () => {
  await invoke("copy_transcript");
  setState("Idle");
});

document.getElementById("btn-close")?.addEventListener("click", async () => {
  await invoke("dismiss_transcript");
  setState("Idle");
});

document.getElementById("btn-retry")?.addEventListener("click", async () => {
  await invoke("retry_recording");
  setState("Idle");
});

document.getElementById("btn-dismiss")?.addEventListener("click", async () => {
  await invoke("dismiss_transcript");
  setState("Idle");
});

// Waveform: poll audio level at ~30fps when recording
let raf = null;
function startWave() {
  if (!wave) return;
  const ctx = wave.getContext("2d");
  const loop = async () => {
    try {
      const level = await invoke("get_audio_level");
      const w = wave.width, h = wave.height;
      ctx.clearRect(0, 0, w, h);
      const bars = 19, bw = 2.5, gap = 2;
      const lv = Math.max(0, Math.min(1, Number(level) || 0));
      for (let i = 0; i < bars; i++) {
        const x = i * (bw + gap) + 8;
        const amp = 0.25 + lv * 0.75 * (0.6 + 0.4 * Math.sin(Date.now() / 200 + i * 0.7));
        const bh = h * amp;
        const y = (h - bh) / 2;
        ctx.fillStyle = "rgba(255,255,255,0.85)";
        ctx.fillRect(x, y, bw, bh);
      }
    } catch {}
    raf = requestAnimationFrame(loop);
  };
  loop();
}
function stopWave() {
  if (raf) cancelAnimationFrame(raf);
  raf = null;
}

// Listen to Rust events
try {
  const { listen } = window.__TAURI__.event;
  listen("agenttalk://state", (e) => setState(e.payload?.phase ?? "Idle"));
  listen("agenttalk://transcript", (e) => {
    transcriptText.textContent = e.payload ?? "";
    setState("TranscriptReady");
    stopWave();
  });
  listen("agenttalk://error", (e) => {
    errorText.textContent = e.payload ?? "Error";
    setState("Error");
    stopWave();
  });
  listen("agenttalk://partial", (e) => {
    // Live preview: optionally show in pill
  });
  listen("agenttalk://recording", () => startWave());
  listen("agenttalk://stopped", () => stopWave());
} catch {}

// Fallback: periodic poll if events not wired yet
setInterval(async () => {
  try {
    const phase = await invoke("get_app_phase");
    // phase is a string from Rust; map loosely
  } catch {}
}, 500);
