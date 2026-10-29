// The view's 帧率 (the request's `fps`: 1…120 frames a second at most; none, 自动): no picture goes into the encoder
// sooner than its slot, by the station's own rule (station/src/mesh/screen-pace.ts `Pacer.wait`): each takes the next
// slot of 1000/fps ms, one late by up to half a slot letting the next come that much sooner, so no second carries more
// than fps + 1 and a capture's jitter does not cut it to fewer.

/// The encoder's frame rate where none is asked (its rate control's frames a second, its key frames' interval): the
/// capture gives as many as the display draws, as the station asks for them.
pub const AUTO_FPS: u32 = 60;
/// The most a view may ask.
pub const MAX_FPS: u32 = 120;
/// A key frame at least this often (ms), however many pictures a second come.
pub const KEY_EVERY_MS: f64 = 10_000.0;

/// The frame rate the encoder is set for (its rate control's bits a picture, its GOP, each picture's duration): the one
/// asked, but no more than AUTO_FPS. A capture asked 90 or 120 seldom gives that many encoded (a 4K desktop on NVENC
/// gave ~55 at 120): an encoder set for 120 would size each picture for 120 a second and send half the bits; set for
/// 60, a second of more pictures than that goes a little over the rate, the station's pace bringing it back.
pub fn encoder_fps(asked: Option<u32>) -> u32 {
    asked.unwrap_or(AUTO_FPS).clamp(1, AUTO_FPS)
}

/// When a key frame is due by time (a GOP counted in pictures comes later the fewer there are): KEY_EVERY_MS after the
/// last one, sent or asked.
#[derive(Default)]
pub struct KeyClock {
    last: Option<f64>,
}

impl KeyClock {
    /// Whether the next picture should be a key frame (ms); none before the first, which is one anyway.
    pub fn due(&self, now: f64) -> bool {
        self.last.is_some_and(|last| now - last >= KEY_EVERY_MS)
    }

    /// A key frame went (or was asked) at `now` (ms).
    pub fn keyed(&mut self, now: f64) {
        self.last = Some(now);
    }
}

/// The frame rate asked, within 1…MAX_FPS; none when not said (or not a number).
pub fn fps(v: Option<u64>) -> Option<u32> {
    v.map(|n| n.clamp(1, MAX_FPS as u64) as u32)
}

pub struct Gate {
    /// ms between pictures (none: as many as come), and when the next may go (ms on the view's clock).
    gap: Option<f64>,
    due: f64,
}

impl Gate {
    pub fn new(fps: Option<u32>) -> Gate {
        Gate { gap: fps.filter(|&f| f > 0).map(|f| 1000.0 / f as f64), due: f64::NEG_INFINITY }
    }

    /// Whether a picture may go now (ms).
    pub fn open(&self, now: f64) -> bool {
        self.gap.is_none() || now >= self.due
    }

    /// One went at `now` (ms).
    pub fn went(&mut self, now: f64) {
        if let Some(gap) = self.gap {
            self.due = (self.due + gap).max(now + gap / 2.0);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Pictures captured every `every` ms and asked for as soon as each went: those that go in `ms`.
    fn run(fps: Option<u32>, every: f64, ms: f64) -> Vec<f64> {
        let mut gate = Gate::new(fps);
        let mut went = Vec::new();
        let mut t = 0.0;
        while t < ms {
            if gate.open(t) {
                gate.went(t);
                went.push(t);
            }
            t += every;
        }
        went
    }

    #[test]
    fn no_more_than_the_rate_asked_in_any_second() {
        for fps in [15, 30, 60, 90, 120] {
            // A capture at 240 Hz, faster than any asked.
            let went = run(Some(fps), 1000.0 / 240.0, 10_000.0);
            for (i, &t) in went.iter().enumerate() {
                let within = went[i..].iter().take_while(|&&u| u < t + 1000.0).count();
                assert!(within <= fps as usize + 1, "{fps}: {within} in the second from {t}");
            }
            // and about as many as asked.
            assert!(went.len() as f64 >= fps as f64 * 10.0 * 0.95, "{fps}: {}", went.len());
        }
    }

    #[test]
    fn a_capture_at_the_rate_asked_keeps_it() {
        // A 120 Hz display asked 120: its every picture (jitter of a capture's clock let through).
        let went = run(Some(120), 1000.0 / 120.0, 1000.0);
        assert_eq!(went.len(), 120);
    }

    #[test]
    fn the_encoder_is_set_for_at_most_auto() {
        assert_eq!(encoder_fps(None), AUTO_FPS);
        assert_eq!(encoder_fps(Some(120)), 60);
        assert_eq!(encoder_fps(Some(90)), 60);
        assert_eq!(encoder_fps(Some(60)), 60);
        assert_eq!(encoder_fps(Some(30)), 30);
        assert_eq!(encoder_fps(Some(15)), 15);
    }

    #[test]
    fn a_key_frame_every_ten_seconds_whatever_the_rate() {
        // ~51 pictures a second (asked 120, a 4K desktop): a key frame every 10 s, not every 1200 pictures (~23 s).
        for every in [1000.0 / 51.0, 1000.0 / 120.0, 1000.0 / 15.0, 700.0] {
            let mut clock = KeyClock::default();
            assert!(!clock.due(0.0));
            clock.keyed(0.0);
            let mut keys = vec![0.0];
            let mut t = every;
            while t < 60_000.0 {
                if clock.due(t) {
                    clock.keyed(t);
                    keys.push(t);
                }
                t += every;
            }
            for pair in keys.windows(2) {
                let gap = pair[1] - pair[0];
                assert!((KEY_EVERY_MS..KEY_EVERY_MS + every + 1e-6).contains(&gap), "{every}: {gap}");
            }
            assert_eq!(keys.len(), 6, "{every}");
        }
        // One asked or made sooner puts the next off.
        let mut clock = KeyClock::default();
        clock.keyed(0.0);
        clock.keyed(6_000.0);
        assert!(!clock.due(10_000.0));
        assert!(clock.due(16_000.0));
    }

    #[test]
    fn none_asked_lets_every_one_go() {
        assert_eq!(run(None, 1000.0 / 144.0, 1000.0).len(), 144);
        assert_eq!(fps(None), None);
        assert_eq!(fps(Some(0)), Some(1));
        assert_eq!(fps(Some(240)), Some(MAX_FPS));
        assert_eq!(fps(Some(90)), Some(90));
    }
}
