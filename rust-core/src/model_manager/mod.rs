/// Model download, caching, and verification.
///
/// Manages the lifecycle of the whisper model file:
///
/// 1. Determines model storage directory
///    (`~/Library/Application Support/AgentTalk/models/`)
/// 2. On first launch, downloads `ggml-large-v3-turbo.bin`
///    from Hugging Face (~1.5 GB)
/// 3. Verifies SHA256 checksum after download
/// 4. Reports download progress to the UI layer
///
/// The model is not bundled with the app binary to keep the
/// notarized .dmg small. Download is synchronous on first launch
/// with a progress indicator shown in the menu bar.
pub struct ModelManager {
    // model_dir: std::path::PathBuf,
    // model_filename: String,
    // expected_sha256: &'static str,
    // auto_download: bool,
}
