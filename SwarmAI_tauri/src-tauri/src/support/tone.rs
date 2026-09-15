//! Audio chime system using synthesized tones.
//!
//! Chimes are rendered as 16-bit mono WAV byte streams on demand and played
//! through the system audio output.  Two built-in chimes are provided:
//!
//! * `play_settle_chime` -- a short two-note tick (E5 down to C5) that plays
//!   when a thread settles.
//! * `play_finish_chime` -- a slightly longer rising fifth (D5 up to A5) that
//!   plays when a turn finishes.

use std::io::Cursor;
use std::sync::Mutex;
use std::time::Duration;

use rodio::{Decoder, OutputStream, OutputStreamHandle, Sink};

// ---------------------------------------------------------------------------
// Tone parameters
// ---------------------------------------------------------------------------

/// A single note within a synthesized chime.
#[derive(Debug, Clone, Copy)]
pub struct Note {
    pub frequency: f64,
    pub onset: f64,
    pub level: f64,
}

/// One partial (harmonic) within a note's tone.
#[derive(Debug, Clone, Copy)]
pub struct Partial {
    pub multiple: f64,
    pub level: f64,
    pub decay: f64,
}

/// A pre-built WAV buffer that can be played through rodio.
#[derive(Debug, Clone)]
pub struct ChimeBuffer {
    pub samples: Vec<i16>,
    pub sample_rate: u32,
}

// ---------------------------------------------------------------------------
// Audio engine
// ---------------------------------------------------------------------------

/// Holds the rodio audio output stream and handle so sound can be played.
pub struct AudioEngine {
    _stream: OutputStream,
    handle: OutputStreamHandle,
}

impl std::fmt::Debug for AudioEngine {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("AudioEngine").finish_non_exhaustive()
    }
}

impl AudioEngine {
    fn new() -> Option<Self> {
        match OutputStream::try_default() {
            Ok((stream, handle)) => Some(Self {
                _stream: stream,
                handle,
            }),
            Err(_) => None,
        }
    }

    fn play(&self, data: &[u8]) {
        let cursor = Cursor::new(data.to_vec());
        if let Ok(source) = Decoder::new(cursor) {
            if let Ok(sink) = Sink::try_new(&self.handle) {
                sink.append(source);
                // Do not block; the sound finishes on its own.
            }
        }
    }
}

// ---------------------------------------------------------------------------
// WAV synthesis
// ---------------------------------------------------------------------------

const SAMPLE_RATE: f64 = 44_100.0;
const ATTACK: f64 = 0.006;
const RELEASE: f64 = 0.08;

/// Render a set of notes with the given partials into a WAV byte vector.
pub fn generate_wave(notes: &[Note], partials: &[Partial], duration: f64) -> Vec<u8> {
    let count = (SAMPLE_RATE * duration).max(1.0) as usize;
    let mut samples = vec![0.0_f64; count];

    for note in notes {
        let start = (note.onset * SAMPLE_RATE).round() as usize;
        for i in start..count {
            let time = (i - start) as f64 / SAMPLE_RATE;
            let onset = if time < ATTACK {
                0.5 - 0.5 * std::f64::consts::PI.cos() * (time / ATTACK)
            } else {
                1.0
            };
            let tone = partials
                .iter()
                .map(|p| {
                    p.level
                        * (-time / p.decay).exp()
                        * (2.0 * std::f64::consts::PI * note.frequency * p.multiple * time).sin()
                })
                .sum::<f64>();
            samples[i] += note.level * onset * tone;
        }
    }

    let fade = (RELEASE * SAMPLE_RATE).round() as usize;
    if fade > 0 && fade < count {
        for i in (count - fade)..count {
            samples[i] *= (count - i) as f64 / fade as f64;
        }
    }

    let peak = samples.iter().map(|s| s.abs()).fold(0.0, f64::max);
    let scale = if peak > 0.0 { 0.9 / peak } else { 0.0 };

    let mut data = Vec::with_capacity(44 + count * 2);
    data.extend_from_slice(b"RIFF");
    data.extend_from_slice(&(36 + count * 2).to_le_bytes());
    data.extend_from_slice(b"WAVE");
    data.extend_from_slice(b"fmt ");
    data.extend_from_slice(&16u32.to_le_bytes());
    data.extend_from_slice(&1u16.to_le_bytes()); // PCM
    data.extend_from_slice(&1u16.to_le_bytes()); // mono
    data.extend_from_slice(&(SAMPLE_RATE as u32).to_le_bytes());
    data.extend_from_slice(&(SAMPLE_RATE as u32 * 2).to_le_bytes());
    data.extend_from_slice(&2u16.to_le_bytes()); // bytes per frame
    data.extend_from_slice(&16u16.to_le_bytes()); // bits per sample
    data.extend_from_slice(b"data");
    data.extend_from_slice(&(count * 2).to_le_bytes());
    for sample in &samples {
        let clamped = (sample * scale * i16::MAX as f64).round().clamp(i16::MIN as f64, i16::MAX as f64) as i16;
        data.extend_from_slice(&clamped.to_le_bytes());
    }
    data
}

// ---------------------------------------------------------------------------
// ToneSynth (mirrors the Swift enum)
// ---------------------------------------------------------------------------

pub struct ToneSynth;

impl ToneSynth {
    pub fn wave(notes: &[Note], partials: &[Partial], duration: f64) -> Vec<u8> {
        generate_wave(notes, partials, duration)
    }
}

// ---------------------------------------------------------------------------
// Settle chime -- E5 down to C5, 0.32 s
// ---------------------------------------------------------------------------

pub fn play_settle_chime() {
    ensure_audio_engine();
    let data = generate_wave(
        &[
            Note { frequency: 659.26, onset: 0.0, level: 0.7 },
            Note { frequency: 523.25, onset: 0.075, level: 1.0 },
        ],
        &[
            Partial { multiple: 1.0, level: 1.0, decay: 0.075 },
            Partial { multiple: 3.0, level: 0.16, decay: 0.02 },
            Partial { multiple: 2.0, level: 0.08, decay: 0.03 },
        ],
        0.32,
    );
    if let Some(engine) = audio_engine().lock().unwrap().as_ref() {
        engine.play(&data);
    }
}

// ---------------------------------------------------------------------------
// Finish chime -- D5 up to A5, 0.7 s
// ---------------------------------------------------------------------------

pub fn play_finish_chime() {
    ensure_audio_engine();
    let data = generate_wave(
        &[
            Note { frequency: 587.33, onset: 0.0, level: 0.8 },
            Note { frequency: 880.0, onset: 0.14, level: 1.0 },
        ],
        &[
            Partial { multiple: 1.0, level: 1.0, decay: 0.14 },
            Partial { multiple: 2.0, level: 0.22, decay: 0.06 },
            Partial { multiple: 4.0, level: 0.08, decay: 0.04 },
        ],
        0.7,
    );
    if let Some(engine) = audio_engine().lock().unwrap().as_ref() {
        engine.play(&data);
    }
}

// ---------------------------------------------------------------------------
// Play a sequence of ToneEvent entries (mirrors the Swift version)
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SoundType {
    Tink,
    Drop,
    Bell,
}

#[derive(Debug, Clone, Copy)]
pub struct ToneEvent {
    pub sound_type: SoundType,
    pub delay_ms: u64,
    pub volume: f32,
}

pub fn play_sequence(sequence: &[ToneEvent]) {
    for event in sequence {
        match event.sound_type {
            SoundType::Tink => play_settle_chime(),
            SoundType::Drop => play_finish_chime(),
            SoundType::Bell => {
                // Generate a bell-like tone.
                let data = generate_wave(
                    &[Note { frequency: 800.0, onset: 0.0, level: 0.5 }],
                    &[
                        Partial { multiple: 1.0, level: 1.0, decay: 0.3 },
                        Partial { multiple: 2.5, level: 0.4, decay: 0.1 },
                        Partial { multiple: 3.0, level: 0.2, decay: 0.05 },
                    ],
                    0.5,
                );
                ensure_audio_engine();
                if let Some(engine) = audio_engine().lock().unwrap().as_ref() {
                    engine.play(&data);
                }
            }
        }
        // Respect the delay_ms between events.
        if event.delay_ms > 0 && event.delay_ms < 2000 {
            std::thread::sleep(Duration::from_millis(event.delay_ms));
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_wave_length() {
        let data = generate_wave(
            &[Note { frequency: 440.0, onset: 0.0, level: 1.0 }],
            &[Partial { multiple: 1.0, level: 1.0, decay: 0.1 }],
            0.1,
        );
        // 44 bytes header + 2 bytes per sample * sample_rate * duration
        let expected_samples = (SAMPLE_RATE * 0.1).round() as usize;
        assert_eq!(data.len(), 44 + expected_samples * 2);
    }

    #[test]
    fn test_wave_has_header() {
        let data = generate_wave(
            &[Note { frequency: 440.0, onset: 0.0, level: 1.0 }],
            &[Partial { multiple: 1.0, level: 1.0, decay: 0.1 }],
            0.01,
        );
        assert_eq!(&data[0..4], b"RIFF");
        assert_eq!(&data[8..12], b"WAVE");
    }

    #[test]
    fn test_without_em_dashes_reused() {
        let input = "works — every time";
        let cleaned = without_em_dashes(input);
        assert_eq!(cleaned, "works - every time");
    }
}

use std::sync::OnceLock;

static AUDIO_ENGINE: OnceLock<Mutex<Option<AudioEngine>>> = OnceLock::new();

fn audio_engine() -> &'static Mutex<Option<AudioEngine>> {
    AUDIO_ENGINE.get_or_init(|| Mutex::new(None))
}

fn ensure_audio_engine() {
    if audio_engine().lock().unwrap().is_none() {
        *audio_engine().lock().unwrap() = AudioEngine::new();
    }
}
