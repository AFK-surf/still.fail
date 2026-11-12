// System output made into 20 ms packets (audio.rs's WASAPI capture: `Runs`), and what goes out for each (`Packets`): the
// PCM as it is, or one Opus packet of it for a view that asked `audioCodec: "opus"` (opus-rs, the encoder of the decoder
// the apps' shell has: client/shell), and nothing once digital silence has lasted QUIET packets (WASAPI's loopback goes
// on giving it while nothing plays: 1.5 Mbit/s of zeros as PCM); shorter, between two sounds, it goes as sound does.
// After a gap (silence left out, a discontinuity, a packet dropped) the encoder starts anew, as the client's decoder
// does then (still.fail Helper's SystemAudio.swift, the same).
const PACKET_FRAMES: usize = 960;
const PACKET_BYTES: usize = PACKET_FRAMES * 4;
const PACKET_US: u64 = 20_000;
/// How far (µs) a buffer's said time may be from where the sound before it ends (by its frames) and still follow on:
/// half a packet, more than a capture's time jitters, less than any gap.
const SLACK: u64 = 10_000;
/// Packets of digital silence in a row from which none is sent (200 ms).
const QUIET: u32 = 10;
const BITRATE: i32 = 64_000;

/// The capture's buffers made into packets of exactly 960 frames. Sound that follows on from the sound before it (its
/// buffer's said time within SLACK of where the run's frames say it starts) is one run, and a packet's time is where it
/// starts in its run by the frames before it, from the run's start, which each buffer draws a 64th of the way to its
/// said time: so neither the said times' jitter nor the two clocks' drift (QPC, the sound card's frames: tens of ppm
/// apart) moves packets off by more than a fraction of a millisecond, and the run never breaks for drift (still.fail
/// Helper's AudioPackets, the same). Sound that does not follow on starts a run of its own, the part of a packet made
/// before it dropped.
pub struct Runs {
    building: Vec<u8>,
    /// The run: when it started (µs), the frames that came in it, those of them in packets made; none before any.
    at: Option<u64>,
    frames: u64,
    made: u64,
    /// How many runs there have been.
    pub runs: u32,
}

impl Runs {
    pub fn new() -> Self {
        Runs { building: Vec::with_capacity(PACKET_BYTES), at: None, frames: 0, made: 0, runs: 0 }
    }

    /// A buffer of interleaved stereo PCM16 captured from `at` (µs): each packet it completes given to `packet` with its
    /// time. `discontinuity`: the capture says it does not follow on.
    pub fn add(&mut self, at: u64, pcm: &[u8], discontinuity: bool, mut packet: impl FnMut(u64, Vec<u8>)) {
        let expected = self.at.map(|start| start as i64 + (self.frames * 1_000_000 / 48_000) as i64);
        match expected {
            Some(e) if !discontinuity && (at as i64 - e).abs() <= SLACK as i64 => {
                self.at = Some((self.at.unwrap() as i64 + (at as i64 - e) / 64) as u64);
            }
            _ => {
                self.building.clear();
                self.at = Some(at);
                self.frames = 0;
                self.made = 0;
                self.runs += 1;
            }
        }
        let start = self.at.unwrap();
        for chunk in pcm.chunks(4) {
            self.building.extend_from_slice(chunk);
            if self.building.len() == PACKET_BYTES {
                let ts = start + self.made * PACKET_US;
                self.made += 1;
                packet(ts, std::mem::replace(&mut self.building, Vec::with_capacity(PACKET_BYTES)));
            }
        }
        self.frames += (pcm.len() / 4) as u64;
    }
}

pub struct Packets {
    opus: Option<Box<opus_rs::OpusEncoder>>,
    /// Where the sound last sent ends (µs); none before any and after silence.
    sent_end: Option<u64>,
    /// Packets of digital silence in a row so far.
    zeros: u32,
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
        Packets { opus: if opus { encoder() } else { None }, sent_end: None, zeros: 0 }
    }

    pub fn codec(&self) -> &'static str {
        if self.opus.is_some() { "opus" } else { "pcm_s16le" }
    }

    /// Message 9's payload for the packet captured from `ts` (µs): its 8 bytes of time, then the PCM or the Opus packet;
    /// none to send (silence, or the encoder gave nothing for it).
    pub fn payload(&mut self, ts: u64, pcm: &[u8]) -> Option<Vec<u8>> {
        if pcm.len() != PACKET_BYTES { return None; }
        if pcm.iter().all(|&b| b == 0) {
            self.zeros += 1;
            if self.zeros >= QUIET {
                self.sent_end = None;
                return None;
            }
        } else {
            self.zeros = 0;
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
        self.sent_end = Some(ts + PACKET_US);
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
        // silence: its first 9 packets (180 ms, a pause between two sounds) go, from the 10th none
        for n in 0..12u64 {
            let sent = packets.payload(1_200_000 + n * 20_000, &[0u8; PACKET_BYTES]);
            assert_eq!(sent.is_some(), n < 9, "packet {n} of silence");
        }
        assert!(packets.payload(1_500_000, &tone(0)).is_some(), "the sound after it is");
    }

    /// Buffers of 10 ms whose said times jitter (±3 ms, now and then ±8: what a capture's clock gives) make packets 20 ms
    /// apart exactly, and the encoder never starts anew; a gap (or a discontinuity said) starts a run of its own.
    #[test]
    fn jittered_capture_times_make_one_run_and_a_gap_another() {
        let mut runs = Runs::new();
        let mut packets = Packets::new(true);
        let mut sent: Vec<u64> = vec![];
        let jitter = [0i64, 3_000, -3_000, 1_000, -2_000, 8_000, -8_000, 2_000, -1_000, 3_000];
        // 10 ms (480 frames) of a tone, the n-th
        let buffer = |n: usize| -> Vec<u8> {
            (0..480).flat_map(|i| {
                let t = (n * 480 + i) as f64 / 48_000.0;
                let v = ((2.0 * std::f64::consts::PI * 440.0 * t).sin() * 0.3 * 32767.0) as i16;
                [v.to_le_bytes(), v.to_le_bytes()].concat()
            }).collect()
        };
        let mut follows = 0;
        for n in 0..200usize {
            let at = (5_000_000 + n as i64 * 10_000 + jitter[n % jitter.len()]) as u64;
            runs.add(at, &buffer(n), false, |ts, pcm| {
                let was = packets.sent_end;
                assert!(packets.payload(ts, &pcm).is_some());
                if was.is_some_and(|end| ts.abs_diff(end) <= SLACK) { follows += 1; }
                sent.push(ts);
            });
        }
        assert_eq!(sent.len(), 100);
        assert!(sent.windows(2).all(|w| (w[1] - w[0]).abs_diff(20_000) <= 300), "20 ms apart, the jitter a 64th of it at most");
        assert_eq!(runs.runs, 1);
        assert_eq!(follows, 99, "one run: the encoder made anew for its first packet alone");
        // 100 ms with nothing captured: a run of its own, its first packet's encoder anew
        let mut after = vec![];
        for n in 0..4usize { runs.add(7_100_000 + n as u64 * 10_000, &buffer(n), false, |ts, _| after.push(ts)); }
        assert_eq!(after.len(), 2);
        assert!(after[0].abs_diff(7_100_000) <= 100 && (after[1] - after[0]).abs_diff(20_000) <= 100);
        assert_eq!(runs.runs, 2);
        let mut said = vec![];
        runs.add(7_140_000, &buffer(0), true, |ts, _| said.push(ts));
        runs.add(7_150_000, &buffer(1), false, |ts, _| said.push(ts));
        assert_eq!(said, vec![7_140_000], "a discontinuity said: anew");
    }

    /// Ten minutes of 10 ms buffers whose said times run 100 ppm fast, or slow, against the frames, and jitter: one run,
    /// every packet, each within 3 ms of when its first frame was captured, and the encoder made anew once.
    #[test]
    fn drift_of_100_ppm_either_way_keeps_one_run_and_packets_on_their_time() {
        let jitter = [0i64, 3_000, -3_000, 1_000, -2_000, 8_000, -8_000, 2_000, -1_000, 3_000];
        let sound: Vec<u8> = (0..480).flat_map(|i| (((i % 96) as i16 - 48) * 100).to_le_bytes().repeat(2)).collect();
        for ppm in [100.0f64, -100.0] {
            let clock = |frame: u64| 1_000_000.0 + frame as f64 * 1_000_000.0 / 48_000.0 * (1.0 + ppm / 1e6);
            let mut runs = Runs::new();
            let mut packets = Packets::new(true);
            let (mut n_packets, mut worst, mut follows) = (0u64, 0f64, 0u64);
            let buffers = 10 * 60 * 100usize;
            for n in 0..buffers {
                let at = (clock(n as u64 * 480) as i64 + jitter[n % jitter.len()]) as u64;
                runs.add(at, &sound, false, |ts, pcm| {
                    worst = worst.max((ts as f64 - clock(n_packets * 960)).abs());
                    if packets.sent_end.is_some_and(|end| ts.abs_diff(end) <= SLACK) { follows += 1; }
                    assert!(packets.payload(ts, &pcm).is_some());
                    n_packets += 1;
                });
            }
            assert_eq!(runs.runs, 1, "{ppm} ppm");
            assert_eq!(n_packets, (buffers * 480 / 960) as u64, "{ppm} ppm: none dropped");
            assert_eq!(follows, n_packets - 1, "{ppm} ppm: the encoder made anew for the first packet alone");
            assert!(worst <= 3_000.0, "{ppm} ppm: {worst} µs off");
        }
    }

    #[test]
    fn pcm_goes_as_it_is_but_silence() {
        let mut packets = Packets::new(false);
        assert_eq!(packets.codec(), "pcm_s16le");
        let sound = tone(0);
        let p = packets.payload(7, &sound).unwrap();
        assert_eq!((&p[..8], &p[8..]), (&7u64.to_be_bytes()[..], &sound[..]));
        // a packet of silence goes (a pause between two sounds); from the 10th in a row none
        let silence: Vec<bool> = (1..=11u64).map(|n| packets.payload(7 + n * 20_000, &[0u8; PACKET_BYTES]).is_some()).collect();
        assert_eq!(silence, [vec![true; 9], vec![false; 2]].concat());
    }
}
