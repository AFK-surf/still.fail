//! A terminal's screen as libghostty-vt keeps it (scripts/native.ts `ghostty-vt`, linked by build.rs): what a
//! terminal's output has made of it so far, so that one who opens it later, or again, is given the screen as it is
//! rather than every byte since it began.
//!
//! Only the few calls this needs, declared by hand from the release's headers (include/ghostty/vt/terminal.h,
//! formatter.h, allocator.h): its C ABI is stable from 1.0.

use std::ffi::c_void;
use std::ptr;

type Result_ = i32;
const SUCCESS: Result_ = 0;
/// GHOSTTY_FORMATTER_OPT_EMIT, a GhosttyFormatterFormat; its VT is 1.
const OPT_EMIT: i32 = 1;
const FORMAT_VT: i32 = 1;
/// GHOSTTY_FORMATTER_OPT_TRIM, a bool: off, so the screen's rows are all there.
const OPT_TRIM: i32 = 3;
/// GHOSTTY_FORMATTER_OPT_EXTRAS, a bitmask: all of them (GHOSTTY_FORMATTER_EXTRAS_ALL), so the modes (the alternate
/// screen, the cursor keys', the mouse's), the cursor, the scrolling region and the rest come back as they were.
const OPT_EXTRAS: i32 = 5;
const EXTRAS_ALL: u32 = 0xFFF;
/// What a cell is said to measure: the screen's pixels are no one's here (only a program that asks for them sees it).
const CELL_W: u32 = 8;
const CELL_H: u32 = 16;

unsafe extern "C" {
    fn ghostty_terminal_new(allocator: *const c_void, terminal: *mut *mut c_void, cols: u16, rows: u16) -> Result_;
    fn ghostty_terminal_free(terminal: *mut c_void);
    fn ghostty_terminal_vt_write(terminal: *mut c_void, data: *const u8, len: usize);
    fn ghostty_terminal_resize(terminal: *mut c_void, cols: u16, rows: u16, cell_w: u32, cell_h: u32) -> Result_;
    fn ghostty_formatter_terminal_new(allocator: *const c_void, formatter: *mut *mut c_void, terminal: *mut c_void) -> Result_;
    fn ghostty_formatter_set(formatter: *mut c_void, option: i32, value: *const c_void) -> Result_;
    fn ghostty_formatter_format_alloc(formatter: *mut c_void, allocator: *const c_void, out: *mut *mut u8, len: *mut usize) -> Result_;
    fn ghostty_formatter_free(formatter: *mut c_void);
    fn ghostty_free(allocator: *const c_void, ptr: *mut u8, len: usize);
}

pub struct Screen(*mut c_void);

// SAFETY: the terminal is used from one thread at a time (the runner holds it behind a mutex); libghostty-vt keeps no
// state of a thread's.
unsafe impl Send for Screen {}

impl Screen {
    pub fn new(cols: u16, rows: u16) -> Result<Screen, String> {
        let mut terminal = ptr::null_mut();
        // SAFETY: a null allocator is the library's own; `terminal` is written on success.
        let r = unsafe { ghostty_terminal_new(ptr::null(), &mut terminal, cols.max(1), rows.max(1)) };
        if r != SUCCESS || terminal.is_null() {
            return Err(format!("libghostty-vt: terminal_new: {r}"));
        }
        Ok(Screen(terminal))
    }

    /// What the terminal's program wrote.
    pub fn write(&mut self, bytes: &[u8]) {
        // SAFETY: a live terminal; the bytes are read during the call only.
        unsafe { ghostty_terminal_vt_write(self.0, bytes.as_ptr(), bytes.len()) }
    }

    pub fn resize(&mut self, cols: u16, rows: u16) {
        // SAFETY: a live terminal.
        unsafe { ghostty_terminal_resize(self.0, cols.max(1), rows.max(1), CELL_W, CELL_H) };
    }

    /// The screen as VT sequences that, written to a terminal of its size that is new, make it this one.
    pub fn snapshot(&self) -> Result<Vec<u8>, String> {
        let mut formatter = ptr::null_mut();
        // SAFETY: a live terminal, which outlives the formatter (freed below); each option is given a value of its type.
        unsafe {
            let r = ghostty_formatter_terminal_new(ptr::null(), &mut formatter, self.0);
            if r != SUCCESS || formatter.is_null() {
                return Err(format!("libghostty-vt: formatter_terminal_new: {r}"));
            }
            let emit = FORMAT_VT;
            let trim = false;
            let extras = EXTRAS_ALL;
            let set = [
                ghostty_formatter_set(formatter, OPT_EMIT, (&raw const emit).cast()),
                ghostty_formatter_set(formatter, OPT_TRIM, (&raw const trim).cast()),
                ghostty_formatter_set(formatter, OPT_EXTRAS, (&raw const extras).cast()),
            ];
            let (mut out, mut len) = (ptr::null_mut(), 0usize);
            let r = if set.iter().all(|&r| r == SUCCESS) { ghostty_formatter_format_alloc(formatter, ptr::null(), &mut out, &mut len) } else { set.into_iter().find(|&r| r != SUCCESS).unwrap() };
            ghostty_formatter_free(formatter);
            if r != SUCCESS {
                return Err(format!("libghostty-vt: format: {r}"));
            }
            let bytes = if out.is_null() { Vec::new() } else { std::slice::from_raw_parts(out, len).to_vec() };
            ghostty_free(ptr::null(), out, len);
            Ok(bytes)
        }
    }
}

impl Drop for Screen {
    fn drop(&mut self) {
        // SAFETY: ours, freed once.
        unsafe { ghostty_terminal_free(self.0) }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_screen_is_given_back_as_what_makes_it_again() {
        let mut screen = Screen::new(20, 4).unwrap();
        screen.write(b"one\r\n\x1b[31mtwo\x1b[0m");
        let snapshot = screen.snapshot().unwrap();
        // Written into a new terminal of its size, it makes the same screen: the same snapshot again.
        let mut again = Screen::new(20, 4).unwrap();
        again.write(&snapshot);
        assert_eq!(again.snapshot().unwrap(), snapshot);
        let text = String::from_utf8_lossy(&snapshot);
        assert!(text.contains("one") && text.contains("two") && text.contains("\x1b["), "{text:?}");
    }

    #[test]
    fn the_alternate_screen_is_given_back_as_the_one_shown() {
        let mut screen = Screen::new(20, 4).unwrap();
        screen.write(b"shell\r\n\x1b[?1049h\x1b[HFULL");
        let mut again = Screen::new(20, 4).unwrap();
        again.write(&screen.snapshot().unwrap());
        let text = String::from_utf8_lossy(&again.snapshot().unwrap()).into_owned();
        assert!(text.contains("FULL") && !text.contains("shell"), "{text:?}");
        screen.resize(30, 6);
        assert!(String::from_utf8_lossy(&screen.snapshot().unwrap()).contains("FULL"));
    }
}
