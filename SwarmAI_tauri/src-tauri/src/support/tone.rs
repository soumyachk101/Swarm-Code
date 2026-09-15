use std::collections::HashMap;

pub struct ToneSynth;

impl ToneSynth {
 pub fn play_sequence(sequence: &[ToneEvent]) {
 // Audio synthesis using rodio or system sounds
 for event in sequence {
 match event.sound_type {
 SoundType::Tink => Self::play_system_sound(SystemSound::Tink),
 SoundType::Drop => Self::play_system_sound(SystemSound::Drop),
 SoundType::Bell => Self::play_system_sound(SystemSound::Bell),
 }
 }
 }

 fn play_system_sound(sound: SystemSound) {
 let _ = std::process::Command::new("afplay")
 .arg("/System/Library/Sounds/Glass.aiff")
 .spawn();
 }
}

#[derive(Debug, Clone)]
pub struct ToneEvent {
 pub sound_type: SoundType,
 pub delay_ms: u64,
 pub volume: f32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SoundType {
 Tink,
 Drop,
 Bell,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SystemSound {
 Tink,
 Drop,
 Bell,
}
