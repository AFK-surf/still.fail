#![cfg(unix)]

//! A terminal kept by the runner (`--pty`): its program on a pseudo-terminal, its size, its screen. As runner.rs, these
//! wait for what the program does, with no limit of time.

use std::io::{BufRead, BufReader, Write};
use std::os::unix::net::UnixStream;
use std::path::PathBuf;
use std::process::{Child, Command, Stdio};

use base64::Engine;
use base64::engine::general_purpose::STANDARD as B64;
use serde_json::{Value, json};

const BIN: &str = env!("CARGO_BIN_EXE_stillfail-runner");

struct Terminal {
    dir: PathBuf,
    info: Value,
    child: Child,
    reader: BufReader<UnixStream>,
    writer: UnixStream,
    /// stdout so far, and its offset.
    out: Vec<u8>,
    at: u64,
    /// What was answered besides output, in order.
    replies: Vec<Value>,
}

impl Terminal {
    fn start(name: &str, size: &str, script: &str) -> Terminal {
        let dir = PathBuf::from(format!("/tmp/sfp-{}-{name}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let mut child = Command::new(BIN)
            .args(["--dir", dir.to_str().unwrap(), "--id", "t", "--pty", size, "--", "/bin/sh", "-c", script])
            .stdout(Stdio::piped())
            .spawn()
            .unwrap();
        let mut line = String::new();
        BufReader::new(child.stdout.take().unwrap()).read_line(&mut line).unwrap();
        let info: Value = serde_json::from_str(&line).unwrap();
        assert_eq!(info["pty"], json!(true), "{info}");
        let stream = UnixStream::connect(info["socket"].as_str().unwrap()).unwrap();
        let mut t = Terminal { dir, info, child, reader: BufReader::new(stream.try_clone().unwrap()), writer: stream, out: vec![], at: 0, replies: vec![] };
        t.send(json!({"op": "attach"}));
        t
    }

    fn send(&mut self, message: Value) {
        self.writer.write_all(format!("{message}\n").as_bytes()).unwrap();
    }

    fn write(&mut self, data: &[u8]) {
        self.send(json!({"op": "write", "data": B64.encode(data)}));
    }

    /// The next message that is not output (output read meanwhile is kept); None at the exit.
    fn next(&mut self) -> Option<Value> {
        loop {
            let mut line = String::new();
            assert!(self.reader.read_line(&mut line).unwrap() > 0, "the runner ended the connection");
            let message: Value = serde_json::from_str(&line).unwrap();
            match message["op"].as_str() {
                Some("attached") => {}
                Some("out") => {
                    assert_eq!(message["stream"], "out", "a terminal writes stdout alone: {message}");
                    assert_eq!(message["at"].as_u64().unwrap(), self.at, "offsets run on: {message}");
                    let data = B64.decode(message["data"].as_str().unwrap()).unwrap();
                    self.at += data.len() as u64;
                    self.out.extend(data);
                    return Some(message);
                }
                Some("exit") => return None,
                _ => {
                    self.replies.push(message.clone());
                    return Some(message);
                }
            }
        }
    }

    fn until_out(&mut self, text: &str) {
        while !String::from_utf8_lossy(&self.out).contains(text) {
            assert!(self.next().is_some(), "it exited before writing {text:?}: {:?}", String::from_utf8_lossy(&self.out));
        }
    }

    fn until_reply(&mut self, op: &str) -> Value {
        loop {
            if let Some(i) = self.replies.iter().position(|r| r["op"] == op) {
                return self.replies.remove(i);
            }
            assert!(self.next().is_some(), "it exited before answering {op}");
        }
    }

    fn until_exit(&mut self) {
        while self.next().is_some() {}
    }
}

impl Drop for Terminal {
    fn drop(&mut self) {
        unsafe {
            libc::kill(-(self.info["pgid"].as_i64().unwrap() as i32), libc::SIGKILL);
            libc::kill(self.info["runner"].as_i64().unwrap() as i32, libc::SIGKILL);
        }
        let _ = self.child.wait();
        let _ = std::fs::remove_dir_all(&self.dir);
    }
}

#[test]
fn its_program_is_on_a_terminal_of_the_size_asked() {
    let mut t = Terminal::start("size", "40x10", r#"[ -t 0 ] && [ -t 1 ] && echo tty; stty size; read line; echo "got:$line""#);
    t.until_out("tty");
    t.until_out("10 40");
    t.write(b"hello\n");
    t.until_out("got:hello");
    t.until_exit();
}

#[test]
fn a_resize_reaches_its_program_and_its_screen() {
    let mut t = Terminal::start("resize", "40x10", r#"printf '\033[2J\033[HREADY'; read a; stty size; read b"#);
    t.until_out("READY");
    t.send(json!({"op": "resize", "cols": 50, "rows": 20}));
    t.write(b"\n");
    t.until_out("20 50");
    t.write(b"\n");
    t.until_exit();
}

#[test]
fn its_screen_is_given_with_how_much_output_made_it() {
    let mut t = Terminal::start("screen", "30x6", r#"printf '\033[2J\033[Hfirst\r\n\033[?1049h\033[Hfull screen'; read a"#);
    t.until_out("full screen");
    let at_least = t.at;
    t.send(json!({"op": "screen"}));
    let screen = t.until_reply("screen");
    let data = String::from_utf8(B64.decode(screen["data"].as_str().unwrap()).unwrap()).unwrap();
    // The screen shown is the alternate one: what was under it is not drawn over it.
    assert!(data.contains("full screen") && !data.contains("first"), "{data:?}");
    assert!(screen["at"].as_u64().unwrap() >= at_least, "{screen}");
    t.write(b"\n");
    t.until_exit();
}

#[test]
fn a_program_on_pipes_is_no_terminal() {
    let dir = PathBuf::from(format!("/tmp/sfp-{}-pipes", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let mut child = Command::new(BIN).args(["--dir", dir.to_str().unwrap(), "--id", "p", "--", "/bin/sh", "-c", "read x"]).stdout(Stdio::piped()).spawn().unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap()).read_line(&mut line).unwrap();
    let info: Value = serde_json::from_str(&line).unwrap();
    assert_eq!(info["pty"], json!(false));
    let mut stream = UnixStream::connect(info["socket"].as_str().unwrap()).unwrap();
    stream.write_all(b"{\"op\":\"screen\"}\n").unwrap();
    let mut reader = BufReader::new(stream.try_clone().unwrap());
    let mut answer = String::new();
    reader.read_line(&mut answer).unwrap();
    assert!(answer.contains("not a terminal"), "{answer}");
    unsafe {
        libc::kill(-(info["pgid"].as_i64().unwrap() as i32), libc::SIGKILL);
        libc::kill(info["runner"].as_i64().unwrap() as i32, libc::SIGKILL);
    }
    let _ = child.wait();
    let _ = std::fs::remove_dir_all(&dir);
}
