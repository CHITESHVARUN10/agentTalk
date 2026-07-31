//! Audio capture via cpal.
//!
//! cpal::Stream is not Send, so it lives in thread_local storage.
//! All FFI calls to start/stop recording come from the main thread.
//! Samples are accumulated in a shared Vec behind Arc<Mutex>.
//! Amplitude is stored as RMS bits in an AtomicU32.

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::Stream;
use std::sync::{
    atomic::{AtomicU32, Ordering},
    Arc, Mutex,
};

pub struct AudioCapture {
    stream: Stream,
    buffer: Arc<Mutex<Vec<f32>>>,
    level: Arc<AtomicU32>,
}

impl AudioCapture {
    pub fn start() -> anyhow::Result<Self> {
        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .ok_or_else(|| anyhow::anyhow!("No input device found"))?;

        let device_name = device.name()?;
        tracing::info!(device = %device_name, "Opening audio input");

        let config: cpal::StreamConfig = cpal::StreamConfig {
            channels: 1,
            sample_rate: cpal::SampleRate(16000),
            buffer_size: cpal::BufferSize::Default,
        };

        let buffer = Arc::new(Mutex::new(Vec::with_capacity(16000 * 90)));
        let level = Arc::new(AtomicU32::new(0));

        let buf_clone = buffer.clone();
        let lvl_clone = level.clone();

        let err_fn = |err| {
            tracing::error!(?err, "Audio stream error");
        };

        let stream = device.build_input_stream(
            &config,
            move |data: &[f32], _: &cpal::InputCallbackInfo| {
                let mut buf = buf_clone.lock().unwrap();
                let max_samples = 16000 * 90;
                if buf.len() + data.len() > max_samples {
                    let excess = (buf.len() + data.len()) - max_samples;
                    if excess < buf.len() {
                        buf.drain(..excess);
                    }
                }
                buf.extend_from_slice(data);

                let sum: f32 = data.iter().map(|s| s * s).sum();
                let rms = (sum / data.len() as f32).sqrt();
                lvl_clone.store(rms.to_bits(), Ordering::Relaxed);
            },
            err_fn,
            None,
        )?;

        stream.play()?;
        tracing::info!("Audio capture started");

        Ok(Self {
            stream,
            buffer,
            level,
        })
    }

    pub fn drain_samples(&self) -> Vec<f32> {
        let mut buf = self.buffer.lock().unwrap();
        std::mem::take(&mut *buf)
    }

    pub fn current_level(&self) -> f32 {
        let bits = self.level.load(Ordering::Relaxed);
        let rms = f32::from_bits(bits);
        (rms / 0.12).min(1.0)
    }

    pub fn stop(self) -> Vec<f32> {
        let samples = self.drain_samples();
        drop(self.stream);
        tracing::info!(samples = samples.len(), "Audio capture stopped");
        samples
    }
}
