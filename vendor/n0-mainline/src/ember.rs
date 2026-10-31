//! ember: what the DHT's socket and lookups went through, for the app's performance record (client/shell's
//! `dht.said`, the core's `dht:` lines). Each line names its DHT (`dht#N`, one per socket made by [`crate::Dht`]'s
//! actor) and a lookup the endpoint it is of (an iroh endpoint's id, its first 4 bytes: the record's station tag).
//!
//! Kept only while the record is on: [`said`] with `keep` takes the lines and keeps them coming until a take without
//! (the core takes them as it records, and without once it stops), however long until the next take: an app
//! suspended for minutes says what its socket did the moment it came back. At most [`KEPT`] lines between two takes
//! (the oldest dropped first, counted), and a failing socket says only its first failures and then each power of two:
//! what it says cannot keep a core busy itself.

use std::collections::VecDeque;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use crate::Id;

/// Lines kept between two takes.
pub const KEPT: usize = 64;
/// Lookups followed at once by a DHT, and endpoints' names kept for their targets: more, and the oldest is forgotten.
const FOLLOWED: usize = 32;

/// A line: when (milliseconds since the Unix epoch) and what.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Said {
    /// When, in milliseconds since the Unix epoch.
    pub at_ms: u64,
    /// What.
    pub text: String,
}

struct Kept {
    lines: VecDeque<Said>,
    dropped: u64,
    /// The endpoint each target is the item of, as lookups asked them (the same key always gives the same target).
    names: VecDeque<(Id, String)>,
}

static KEPT_LINES: Mutex<Kept> = Mutex::new(Kept { lines: VecDeque::new(), dropped: 0, names: VecDeque::new() });
static KEEPING: AtomicBool = AtomicBool::new(false);
static DHTS: AtomicU64 = AtomicU64::new(1);

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64)
}

fn keeping() -> bool {
    KEEPING.load(Ordering::Relaxed)
}

fn kept() -> std::sync::MutexGuard<'static, Kept> {
    KEPT_LINES.lock().unwrap_or_else(|e| e.into_inner())
}

/// The next DHT's number (`dht#N`).
pub(crate) fn next_dht() -> u64 {
    DHTS.fetch_add(1, Ordering::Relaxed)
}

/// A line of DHT `dht` kept, while lines are taken (`text` worked out only then).
pub(crate) fn say(dht: u64, text: impl FnOnce() -> String) {
    if !keeping() {
        return;
    }
    let now = now_ms();
    let text = format!("dht#{dht} {}", text());
    let mut kept = kept();
    if kept.lines.len() >= KEPT {
        kept.lines.pop_front();
        kept.dropped += 1;
    }
    kept.lines.push_back(Said { at_ms: now, text });
}

/// Whether the `n`th failure in a row is said: the first three, then each power of two.
pub(crate) fn says_failure(n: u32) -> bool {
    n <= 3 || n.is_power_of_two()
}

/// With `keep`: the lines since the last take, and how many were dropped for want of room, lines kept from now on.
/// Without: none, and none kept from now on.
pub fn said(keep: bool) -> (Vec<Said>, u64) {
    KEEPING.store(keep, Ordering::Relaxed);
    let mut kept = kept();
    let dropped = std::mem::take(&mut kept.dropped);
    let lines = kept.lines.drain(..).collect();
    if keep { (lines, dropped) } else { (Vec::new(), 0) }
}

/// The item a key (an iroh endpoint's id) signs is looked up under `target`: lookups of it are named by the key.
pub(crate) fn named(target: Id, public_key: &[u8; 32]) {
    if !keeping() {
        return;
    }
    let mut kept = kept();
    if kept.names.iter().any(|(id, _)| *id == target) {
        return;
    }
    if kept.names.len() >= FOLLOWED {
        kept.names.pop_front();
    }
    kept.names.push_back((target, public_key[..4].iter().map(|b| format!("{b:02x}")).collect()));
}

fn name(target: &Id) -> Option<String> {
    kept().names.iter().find(|(id, _)| id == target).map(|(_, name)| name.clone())
}

/// The lookups of named items one DHT's actor has going: when each was asked and how many answers came. A target asked
/// again while its lookup goes joins it (the actor runs one query for it), and is said so.
#[derive(Debug, Default)]
pub(crate) struct Lookups {
    going: Vec<(Id, String, Instant, u32)>,
}

impl Lookups {
    pub(crate) fn asked(&mut self, dht: u64, target: Id) {
        let Some(key) = name(&target) else { return };
        if self.going.iter().any(|(id, ..)| *id == target) {
            return say(dht, || format!("lookup {key} asked again, joining the one going"));
        }
        if self.going.len() >= FOLLOWED {
            self.going.remove(0);
        }
        say(dht, || format!("lookup {key} asked"));
        self.going.push((target, key, Instant::now(), 0));
    }

    pub(crate) fn answered(&mut self, dht: u64, target: &Id) {
        let Some((_, key, asked, answers)) = self.going.iter_mut().find(|(id, ..)| id == target) else { return };
        *answers += 1;
        if *answers == 1 {
            say(dht, || format!("lookup {key} first answer after {}ms", asked.elapsed().as_millis()));
        }
    }

    pub(crate) fn done(&mut self, dht: u64, target: &Id) {
        let Some(at) = self.going.iter().position(|(id, ..)| id == target) else { return };
        let (_, key, asked, answers) = self.going.remove(at);
        say(dht, || format!("lookup {key} done after {}ms: {answers} answer(s)", asked.elapsed().as_millis()));
    }
}

/// Tests that take the lines, or make a socket fail, one at a time: the lines are global.
#[cfg(test)]
pub(crate) static SERIAL: Mutex<()> = Mutex::new(());

#[cfg(test)]
pub(crate) fn reset() {
    KEEPING.store(false, Ordering::Relaxed);
    let mut kept = kept();
    kept.lines.clear();
    kept.dropped = 0;
    kept.names.clear();
}

#[cfg(test)]
mod test {
    use super::*;

    #[test]
    fn kept_only_while_taken_bounded_and_counted() {
        let _serial = SERIAL.lock().unwrap_or_else(|e| e.into_inner());
        reset();
        say(1, || "before anyone took".into());
        assert_eq!(said(true), (vec![], 0));

        for i in 0..KEPT + 5 {
            say(1, || format!("line {i}"));
        }
        let (lines, dropped) = said(true);
        assert_eq!(lines.len(), KEPT);
        assert_eq!(dropped, 5);
        assert_eq!(lines[0].text, "dht#1 line 5");
        assert_eq!(said(true), (vec![], 0));

        // turned off: what was kept is dropped, and nothing more is kept
        say(1, || "kept".into());
        assert_eq!(said(false), (vec![], 0));
        say(1, || "after it was turned off".into());
        assert_eq!(said(true), (vec![], 0));

        // two DHTs looking up the same endpoint: each its own lookup, named alike
        let target = Id::random();
        named(target, &[0xab; 32]);
        let (mut one, mut two) = (Lookups::default(), Lookups::default());
        one.asked(1, target);
        two.asked(2, target);
        one.asked(1, target);
        two.answered(2, &target);
        two.done(2, &target);
        one.answered(1, &target);
        one.answered(1, &target);
        one.done(1, &target);
        one.done(1, &target);
        // an item not named (not an endpoint's lookup): not followed
        one.asked(1, Id::random());
        let texts: Vec<String> = said(true).0.into_iter().map(|s| s.text).collect();
        let starts = ["dht#1 lookup abababab asked", "dht#2 lookup abababab asked", "dht#1 lookup abababab asked again, joining the one going", "dht#2 lookup abababab first answer after ", "dht#2 lookup abababab done after ", "dht#1 lookup abababab first answer after ", "dht#1 lookup abababab done after "];
        assert_eq!(texts.len(), starts.len(), "{texts:?}");
        for (text, start) in texts.iter().zip(starts) {
            assert!(text.starts_with(start), "{text:?} is not {start:?}…");
        }
        assert!(texts[4].ends_with(": 1 answer(s)") && texts[6].ends_with(": 2 answer(s)"), "{texts:?}");

        let says: Vec<u32> = (1..=40).filter(|&n| says_failure(n)).collect();
        assert_eq!(says, [1, 2, 3, 4, 8, 16, 32]);
        reset();
    }
}
