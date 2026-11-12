// What goes out for each 20 ms packet of system output (audio.rs): the PCM as it is, or one Opus packet of it for a
// view that asked `audioCodec: "opus"` (opus-rs, the encoder of the decoder the apps' shell has: client/shell), and
// nothing for digital silence (WASAPI's loopback goes on giving it while nothing plays: 1.5 Mbit/s of zeros as PCM).
// After a gap (silence left out, a discontinuity) the encoder starts anew, as the client's decoder does then.
const PACKET_FRAMES: usize = 960;
const PACKET_BYTES: usize = PACKET_FRAMES * 4;
/// How far (µs) a packet's capture time may be from where the last one sent ended and still follow on from it.
const SLACK: u64 = 5_000;
const BITRATE: i32 = 64_000;

pub struct Packets {
    opus: Option<Box<opus_rs::OpusEncoder>>,
    /// Where the sound last sent ends (µs); none before any and after silence.
    sent_end: Option<u64>,
}

fn encoder() -> Option<Box<opus_rs::OpusEncoder>> {
    let mut e = opus_rs::OpusEncoder::new(48_000, 2, opus_rs::Application::Audio).ok()?;
    e.bitrate_bps = BITRATE;
    e.complexity = 10;
    Some(Box::new(e))
}

impl Packets {
    /// Opus where asked and it can be made, else PCM.
    pub fn new(opus: bool) -> Self {
        Packets { opus: if opus { encoder() } else { None }, sent_end: None }
    }

    pub fn codec(&self) -> &'static str {
        if self.opus.is_some() { "opus" } else { "pcm_s16le" }
    }

    /// Message 9's payload for the packet captured from `ts` (µs): its 8 bytes of time, then the PCM or the Opus packet;
    /// none to send (silence, or the encoder gave nothing for it).
    pub fn payload(&mut self, ts: u64, pcm: &[u8]) -> Option<Vec<u8>> {
        if pcm.len() != PACKET_BYTES { return None; }
        if pcm.iter().all(|&b| b == 0) {
            self.sent_end = None;
            return None;
        }
        let mut payload = ts.to_be_bytes().to_vec();
        match &mut self.opus {
            None => payload.extend_from_slice(pcm),
            Some(e) => {
                if !self.sent_end.is_some_and(|end| ts.abs_diff(end) <= SLACK) {
                    if let Some(fresh) = encoder() { *e = fresh; }
                }
                let samples: Vec<i16> = pcm.chunks_exact(2).map(|b| i16::from_le_bytes([b[0], b[1]])).collect();
                let mut out = [0u8; 1275];
                let n = e.encode_i16(&samples, PACKET_FRAMES, &mut out).ok().filter(|&n| n > 0)?;
                payload.extend_from_slice(&out[..n]);
            }
        }
        self.sent_end = Some(ts + 20_000);
        Some(payload)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 20 ms of a tone from `at` (in frames): 440 Hz on the left, 660 Hz on the right, 0.3 of full scale.
    fn tone(at: usize) -> Vec<u8> {
        (0..PACKET_FRAMES).flat_map(|i| {
            let t = (at + i) as f64 / 48_000.0;
            let l = ((2.0 * std::f64::consts::PI * 440.0 * t).sin() * 0.3 * 32767.0) as i16;
            let r = ((2.0 * std::f64::consts::PI * 660.0 * t).sin() * 0.3 * 32767.0) as i16;
            [l.to_le_bytes(), r.to_le_bytes()].concat()
        }).collect()
    }

    #[test]
    fn opus_packets_decode_to_the_sound_and_silence_goes_unsent() {
        let mut packets = Packets::new(true);
        assert_eq!(packets.codec(), "opus");
        let mut decoder = opus_rs::OpusDecoder::new(48_000, 2).unwrap();
        let mut level = 0.0;
        for n in 0..10 {
            let p = packets.payload(1_000_000 + n as u64 * 20_000, &tone(n * PACKET_FRAMES)).unwrap();
            assert_eq!(u64::from_be_bytes(p[..8].try_into().unwrap()), 1_000_000 + n as u64 * 20_000);
            // a twentieth of PCM's bytes, about
            assert!(p.len() - 8 < 400, "{} bytes", p.len() - 8);
            let mut pcm = [0f32; PACKET_FRAMES * 2];
            assert_eq!(decoder.decode(&p[8..], PACKET_FRAMES, &mut pcm).unwrap(), PACKET_FRAMES);
            level = (pcm.iter().step_by(2).map(|v| (*v as f64).powi(2)).sum::<f64>() / PACKET_FRAMES as f64).sqrt();
        }
        // a sine of 0.3: 0.21 RMS
        assert!((0.18..0.25).contains(&level), "{level}");
        assert_eq!(packets.payload(1_200_000, &[0u8; PACKET_BYTES]), None, "silence is not sent");
        assert!(packets.payload(1_500_000, &tone(0)).is_some(), "the sound after it is");
    }

    #[test]
    fn pcm_goes_as_it_is_but_silence() {
        let mut packets = Packets::new(false);
        assert_eq!(packets.codec(), "pcm_s16le");
        let sound = tone(0);
        let p = packets.payload(7, &sound).unwrap();
        assert_eq!((&p[..8], &p[8..]), (&7u64.to_be_bytes()[..], &sound[..]));
        assert_eq!(packets.payload(20_007, &[0u8; PACKET_BYTES]), None);
    }
}
